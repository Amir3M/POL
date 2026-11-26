package service

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net"
	"net/netip"
	"strings"
	"sync"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/config"
	"github.com/armanlife/arman-vpn-client/core/internal/proxy"
)

const sharedProxyMaxConnections = 128

// SharedProxyInfo is sent only through the native Android method channel.
type SharedProxyInfo struct {
	Address  string `json:"address,omitempty"`
	Port     int    `json:"port,omitempty"`
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
}

type sharedProxySession struct {
	listener *net.TCPListener
	subnet   netip.Prefix

	// Both are guarded by the daemon's sharedProxy mutex.
	info   SharedProxyInfo
	access *sharedProxyAccess
}

// A credential generation owns both sides of its live connections. Closing
// it also rejects any upstream dial that was still pending when it closed.
type sharedProxyAccess struct {
	daemon *Daemon
	server *proxy.SOCKSServer

	mu     sync.Mutex
	active map[net.Conn]struct{}
	closed bool
}

// SetSharedProxy exposes the existing proxy protocol on the selected private
// Android LAN address. The ordinary proxy must already be loopback-only.
func (d *Daemon) SetSharedProxy(address string, prefixBits int) (SharedProxyInfo, error) {
	d.sharedProxy.mu.Lock()
	defer d.sharedProxy.mu.Unlock()

	if address == "" {
		d.closeSharedProxyLocked()
		return SharedProxyInfo{}, nil
	}
	ip, subnet, err := sharedProxySubnet(address, prefixBits)
	if err != nil {
		d.closeSharedProxyLocked()
		return SharedProxyInfo{}, err
	}
	if err := d.sharedProxyAvailable(); err != nil {
		return SharedProxyInfo{}, err
	}
	if running := d.sharedProxy.session; running != nil {
		if running.info.Address == ip.String() && running.subnet == subnet {
			return running.info, nil
		}
		d.closeSharedProxyLocked()
	}

	listener, err := net.ListenTCP("tcp4", net.TCPAddrFromAddrPort(netip.AddrPortFrom(ip, 0)))
	if err != nil {
		return SharedProxyInfo{}, err
	}
	info := SharedProxyInfo{
		Address: ip.String(),
		Port:    listener.Addr().(*net.TCPAddr).Port,
	}
	cfg := d.config().Proxy
	info.Username, info.Password = cfg.Username, cfg.Password
	if d.sharedProxy.rotatedPassword != "" {
		info.Username, info.Password = "share", d.sharedProxy.rotatedPassword
	}
	// SOCKS5 stores credential lengths in one byte; HTTP Basic separates
	// its username from its password with a colon.
	if !validShareLogin(info.Username, info.Password) {
		info.Username, info.Password, err = newSharedProxyCredentials()
		if err != nil {
			_ = listener.Close()
			return SharedProxyInfo{}, err
		}
	}

	session := &sharedProxySession{
		listener: listener,
		subnet:   subnet,
		info:     info,
		access:   d.newSharedProxyAccess(info),
	}
	d.sharedProxy.session = session
	go d.serveSharedProxy(session)
	return info, nil
}

// call with the sharedProxy lock held. A restart may briefly drop the
// ordinary listener, so only the initial activation requires it to be ready.
func (d *Daemon) sharedProxyAvailable() error {
	if !d.privateDashboard || !d.IsOn() {
		return errors.New("start the Android proxy before sharing it")
	}
	select {
	case <-d.stop:
		return errors.New("the proxy is stopping")
	default:
	}
	if !hostIsLoopbackListen(d.config().Proxy.Listen) {
		return errors.New("set the ordinary proxy to loopback before sharing")
	}
	engine := d.currentEngine()
	if engine == nil && d.sharedProxy.session == nil {
		return errors.New("wait for the Android proxy to start")
	}
	if engine != nil && !hostIsLoopbackListen(engine.listener.Addr().String()) {
		return errors.New("wait for the ordinary proxy to restart on loopback")
	}
	return nil
}

func sharedProxySubnet(address string, prefixBits int) (netip.Addr, netip.Prefix, error) {
	ip, err := netip.ParseAddr(address)
	if err != nil || !ip.Is4() || !ip.IsPrivate() || prefixBits < 8 || prefixBits > 31 {
		return netip.Addr{}, netip.Prefix{}, errors.New("sharing requires a private IPv4 network")
	}
	return ip, netip.PrefixFrom(ip, prefixBits).Masked(), nil
}

func validShareLogin(user, password string) bool {
	return user != "" && password != "" && len(user) <= 255 && len(password) <= 255 &&
		!strings.ContainsAny(user, ":\x00\r\n") && !strings.ContainsAny(password, "\x00\r\n")
}

func newSharedProxyCredentials() (string, string, error) {
	var key [24]byte
	if _, err := rand.Read(key[:]); err != nil {
		return "", "", err
	}
	return "share", base64.RawURLEncoding.EncodeToString(key[:]), nil
}

// RotateSharedProxyCredentials replaces the login on the existing socket
// and immediately disconnects clients authenticated with the old login.
func (d *Daemon) RotateSharedProxyCredentials() (SharedProxyInfo, error) {
	d.sharedProxy.mu.Lock()
	defer d.sharedProxy.mu.Unlock()
	session := d.sharedProxy.session
	if session == nil {
		return SharedProxyInfo{}, errors.New("the shared proxy is not running")
	}
	if err := d.sharedProxyAvailable(); err != nil {
		return SharedProxyInfo{}, err
	}
	user, password, err := newSharedProxyCredentials()
	if err != nil {
		return SharedProxyInfo{}, err
	}
	d.sharedProxy.rotatedPassword = password
	info := session.info
	info.Username, info.Password = user, password
	session.access.close()
	session.access, session.info = d.newSharedProxyAccess(info), info
	return info, nil
}

func (d *Daemon) newSharedProxyAccess(info SharedProxyInfo) *sharedProxyAccess {
	access := &sharedProxyAccess{
		daemon: d,
		active: make(map[net.Conn]struct{}),
	}
	server := proxy.NewSOCKSServer(access, config.HandshakeTimeout, config.IdleTimeout, sharedProxyMaxConnections)
	server.Auth = proxy.SOCKSCredentials(info.Username, info.Password)
	server.Notices, server.Conns, server.Inbound = d.notices, d.conns, "share"
	server.Transport = func() string {
		if engine := d.currentEngine(); engine != nil {
			return engine.currentTransport()
		}
		return ""
	}
	access.server = server
	return access
}

// CloseSharedProxy stops sharing without changing the ordinary proxy or
// persisting the shared endpoint and login.
func (d *Daemon) CloseSharedProxy() {
	d.sharedProxy.mu.Lock()
	defer d.sharedProxy.mu.Unlock()
	d.closeSharedProxyLocked()
}

func (d *Daemon) closeSharedProxyLocked() {
	if session := d.sharedProxy.session; session != nil {
		d.sharedProxy.session = nil
		_ = session.listener.Close()
		session.access.close()
	}
}

func (d *Daemon) serveSharedProxy(session *sharedProxySession) {
	var retry time.Duration
	for {
		conn, err := session.listener.AcceptTCP()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			retry = min(max(2*retry, 5*time.Millisecond), time.Second)
			time.Sleep(retry)
			continue
		}
		retry = 0
		peer := conn.RemoteAddr().(*net.TCPAddr).AddrPort().Addr().Unmap()
		if !peer.IsPrivate() || !session.subnet.Contains(peer) {
			_ = conn.Close()
			continue
		}
		d.sharedProxy.mu.Lock()
		access := session.access
		d.sharedProxy.mu.Unlock()
		client, ok := access.track(conn)
		if ok {
			go access.server.ServeConn(client)
		}
	}
}

// OpenTunnel deliberately uses the upstream controller directly. The
// ordinary routed opener can send direct traffic for local rules or push
// services, which is incompatible with a tunnel-only shared endpoint.
func (a *sharedProxyAccess) OpenTunnel(authority string) (net.Conn, error) {
	return a.OpenTunnelForClient(authority, "")
}

func (a *sharedProxyAccess) OpenTunnelForClient(authority, client string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(authority)
	if err != nil || !proxy.PortAllowed(port) || !sharedProxyTarget(host) {
		return nil, proxy.ErrBlockedByRule
	}
	a.mu.Lock()
	closed := a.closed
	a.mu.Unlock()
	if closed || !a.daemon.IsOn() {
		return nil, net.ErrClosed
	}
	engine := a.daemon.currentEngine()
	if engine == nil {
		return nil, errors.New("the VPN tunnel is unavailable")
	}
	upstream := engineUpstream{d: a.daemon, engine: engine}
	conn, err := upstream.OpenTunnelForClient(authority, client)
	if err != nil {
		return nil, err
	}
	tunnel, ok := a.track(conn)
	if !ok {
		return nil, net.ErrClosed
	}
	return tunnel, nil
}

func sharedProxyTarget(host string) bool {
	if ip, err := netip.ParseAddr(host); err == nil {
		ip = ip.Unmap()
		return ip.Zone() == "" && ip.IsGlobalUnicast() && !ip.IsPrivate()
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	return strings.Contains(host, ".") && !strings.HasSuffix(host, ".local") && !strings.HasSuffix(host, ".localhost")
}

func (a *sharedProxyAccess) track(conn net.Conn) (net.Conn, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.closed {
		_ = conn.Close()
		return nil, false
	}
	a.active[conn] = struct{}{}
	return &sharedProxyConn{Conn: conn, access: a}, true
}

func (a *sharedProxyAccess) close() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.closed = true
	for conn := range a.active {
		_ = conn.Close()
	}
	clear(a.active)
}

type sharedProxyConn struct {
	net.Conn
	access *sharedProxyAccess
}

func (c *sharedProxyConn) Close() error {
	c.access.mu.Lock()
	delete(c.access.active, c.Conn)
	c.access.mu.Unlock()
	return c.Conn.Close()
}

func (c *sharedProxyConn) CloseWrite() error {
	if cw, ok := c.Conn.(interface{ CloseWrite() error }); ok {
		return cw.CloseWrite()
	}
	return nil
}
