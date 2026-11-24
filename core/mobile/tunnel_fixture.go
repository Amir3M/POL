//go:build poltunneltest

package mobile

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/accounts"
	"github.com/armanlife/arman-vpn-client/core/internal/config"
	"github.com/armanlife/arman-vpn-client/core/internal/controlplane"
	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
	"github.com/armanlife/arman-vpn-client/core/internal/guardian"
	"github.com/armanlife/arman-vpn-client/core/internal/proxy"
	"github.com/armanlife/arman-vpn-client/core/internal/service"
)

const (
	fixtureGuardianHost = "pol-tunnel-test.invalid"
	fixtureQuota        = 16 << 20
	fixtureTokenTTL     = time.Hour
	fixtureDirPrefix    = "pol-tunnel-test-"
)

var (
	fixtureLifecycle sync.Mutex
	activeFixture    atomic.Pointer[tunnelFixture]
)

type tunnelFixture struct {
	dir              string
	refresh, access  string
	pass             string
	proof            string
	resetAt          time.Time
	origin, upstream *http.Server

	tokenRefreshed, proxyAuthorized atomic.Bool
	requests, bytesUp, bytesDown    atomic.Int64
	transferred                     atomic.Int64
	renewals                        atomic.Int64
}

func init() {
	// Tagged builds never restore an external transport, including between
	// fixture runs, so a late background request cannot escape to the network.
	controlplane.SetTransport(fixtureTransport{})
}

// StartTunnelTest starts an isolated synthetic account and authenticated local
// upstream. The Android service still opens the real TUN with TunConfig.
func StartTunnelTest(dataRoot, sessionID string) error {
	fixtureLifecycle.Lock()
	defer fixtureLifecycle.Unlock()

	if activeFixture.Load() != nil || Running() {
		return errors.New("a tunnel test is already running")
	}
	if dataRoot == "" || len(sessionID) < 16 || len(sessionID) > 128 {
		return errors.New("a local tunnel test session is required")
	}
	if err := os.MkdirAll(dataRoot, 0o700); err != nil {
		return err
	}
	entries, err := os.ReadDir(dataRoot)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), fixtureDirPrefix) {
			if err := os.RemoveAll(filepath.Join(dataRoot, entry.Name())); err != nil {
				return err
			}
		}
	}
	dir, err := os.MkdirTemp(dataRoot, fixtureDirPrefix)
	if err != nil {
		return err
	}
	now := time.Now()
	refresh := sha256.Sum256([]byte(sessionID + rand.Text()))
	f := &tunnelFixture{
		dir: dir, refresh: hex.EncodeToString(refresh[:]), access: rand.Text(), proof: rand.Text(),
		resetAt: now.Add(24 * time.Hour).UTC(),
	}
	claims, _ := json.Marshal(map[string]int64{
		"iat": now.Unix(), "nbf": now.Unix(), "exp": now.Add(fixtureTokenTTL).Unix(),
	})
	f.pass = "fixture." + base64.RawURLEncoding.EncodeToString(claims) + "." + rand.Text()
	if err := f.start(); err != nil {
		f.close()
		return err
	}
	return nil
}

func (f *tunnelFixture) start() error {
	originListener, err := net.Listen("unix", filepath.Join(f.dir, "origin.sock"))
	if err != nil {
		return err
	}
	f.origin = &http.Server{
		Handler: http.HandlerFunc(f.serveOrigin), ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second,
	}
	go func() {
		_ = f.origin.Serve(originListener)
	}()

	certificate, roots, err := fixtureCertificate()
	if err != nil {
		return err
	}
	upstreamListener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return err
	}
	f.upstream = &http.Server{
		Addr: upstreamListener.Addr().String(),
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			f.serveConnect(w, r, originListener.Addr().String())
		}),
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig: &tls.Config{
			MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{certificate},
			NextProtos: []string{"http/1.1"},
		},
	}
	go func() {
		_ = f.upstream.ServeTLS(upstreamListener, "", "")
	}()

	cfg := config.Default()
	cfg.Proxy.Listen = "127.0.0.1:0"
	cfg.Proxy.Server = "https://" + upstreamListener.Addr().String()
	cfg.Proxy.Transport = "h1"
	cfg.Dashboard.Enabled = false
	cfg.Routing.Enabled = false
	cfg.Network.GuardianEndpoint = "https://" + fixtureGuardianHost
	cfg.Network.APIRelayEnabled, cfg.Network.SharedRelayEnabled = false, false
	cfg.Network.HelloSplit = "off"
	cfg.DNS.FallbackToSystem = false
	if err := config.Save(filepath.Join(f.dir, config.FileName), cfg); err != nil {
		return err
	}

	store, err := accounts.OpenStore(f.dir)
	if err != nil {
		return err
	}
	if _, _, err := store.Add("pol-tunnel-test@invalid.example", &fxa.SavedTokens{
		RefreshToken: f.refresh,
	}, time.Now()); err != nil {
		return err
	}

	proxy.SetUpstreamRoots(roots)
	activeFixture.Store(f)
	if err := start(f.dir, true, (*service.Daemon).RestrictToTunnelFixture); err != nil {
		activeFixture.Store(nil)
		return err
	}
	Connect()
	return nil
}

// StopTunnelTest closes the daemon and both loopback servers and removes all
// disposable account, configuration and TUN files.
func StopTunnelTest() {
	fixtureLifecycle.Lock()
	defer fixtureLifecycle.Unlock()

	if f := activeFixture.Swap(nil); f != nil {
		Stop()
		f.close()
	}
}

func (f *tunnelFixture) close() {
	if f.upstream != nil {
		_ = f.upstream.Close()
	}
	if f.origin != nil {
		_ = f.origin.Close()
	}
	_ = os.RemoveAll(f.dir)
}

// RenewTunnelTest exercises synthetic OAuth refresh without restarting the TUN.
func RenewTunnelTest() error {
	fixtureLifecycle.Lock()
	defer fixtureLifecycle.Unlock()

	f := activeFixture.Load()
	mu.Lock()
	d := running
	mu.Unlock()
	if f == nil || d == nil {
		return errors.New("the test tunnel must be connected before renewal")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := d.RenewTunnelFixtureSession(ctx); err != nil {
		return err
	}
	f.renewals.Add(1)
	return nil
}

type fixtureStatus struct {
	State           string `json:"state"`
	SessionReady    bool   `json:"sessionReady"`
	TokenRefreshed  bool   `json:"tokenRefreshed"`
	SessionRenewed  bool   `json:"sessionRenewed"`
	Renewals        int64  `json:"renewals"`
	ProxyAuthorized bool   `json:"proxyAuthorized"`
	Connected       bool   `json:"connected"`
	Requests        int64  `json:"requests"`
	BytesUp         int64  `json:"bytesUp"`
	BytesDown       int64  `json:"bytesDown"`
	QuotaLimit      *int64 `json:"quotaLimit"`
	QuotaRemaining  *int64 `json:"quotaRemaining"`
	FailureCode     string `json:"failureCode,omitempty"`
}

// TunnelTestStatus returns only observable fixture stages and byte counts.
func TunnelTestStatus() string {
	status := fixtureStatus{State: "disconnected"}
	if f := activeFixture.Load(); f != nil {
		status.SessionReady = true
		status.TokenRefreshed = f.tokenRefreshed.Load()
		status.Renewals = f.renewals.Load()
		status.SessionRenewed = status.Renewals > 0
		status.ProxyAuthorized = f.proxyAuthorized.Load()
		status.Requests, status.BytesUp, status.BytesDown = f.requests.Load(), f.bytesUp.Load(), f.bytesDown.Load()
		status.State = "connecting"

		mu.Lock()
		d := running
		mu.Unlock()
		if d == nil {
			status.State, status.FailureCode = "error", "fixture_core_stopped"
		} else if view, err := d.StatusView(); err != nil {
			status.State, status.FailureCode = "error", "fixture_status_failed"
		} else if view.ConnectFailure != "" {
			status.State, status.FailureCode = "error", "fixture_connection_failed"
		} else if view.Pass != nil && view.Pass.Accepting && !view.ConnectPending {
			status.State, status.Connected = "connected", true
		}
		if status.ProxyAuthorized {
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			if usage, err := guardian.FetchProxyUsage(ctx, "https://"+fixtureGuardianHost, f.access); err == nil {
				status.QuotaLimit, status.QuotaRemaining = &usage.Limit, &usage.Remaining
			}
			cancel()
		}
	}
	data, _ := json.Marshal(status)
	return string(data)
}

type fixtureTransport struct{}

var errOutsideTunnelFixture = errors.New("request is outside the tunnel test fixture")

func (fixtureTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if req.Body != nil {
		defer req.Body.Close()
	}
	if err := req.Context().Err(); err != nil {
		return nil, err
	}
	f := activeFixture.Load()
	if f == nil || req.URL.Scheme != "https" || req.URL.RawQuery != "" {
		return nil, errOutsideTunnelFixture
	}
	headers := make(http.Header)
	headers.Set("Cache-Control", "no-store")
	var body []byte
	switch {
	case req.Method == http.MethodPost &&
		req.URL.Host == "api.accounts.firefox.com" && req.URL.Path == "/v1/oauth/token":
		var payload struct {
			Grant   string `json:"grant_type"`
			Refresh string `json:"refresh_token"`
		}
		if req.Body == nil || json.NewDecoder(io.LimitReader(req.Body, 4096)).Decode(&payload) != nil ||
			payload.Grant != "refresh_token" || !fixtureMatch(payload.Refresh, f.refresh) {
			return nil, errors.New("invalid synthetic refresh request")
		}
		body, _ = json.Marshal(fxa.TokenResponse{
			AccessToken: f.access, RefreshToken: f.refresh, TokenType: "bearer",
			ExpiresIn: int(fixtureTokenTTL.Seconds()),
		})
		f.tokenRefreshed.Store(true)
	case (req.Method == http.MethodGet || req.Method == http.MethodHead) &&
		req.URL.Host == fixtureGuardianHost && req.URL.Path == "/api/v1/fpn/token":
		if !fixtureMatch(req.Header.Get("Authorization"), "Bearer "+f.access) {
			return nil, errors.New("invalid synthetic access token")
		}
		headers.Set("X-Quota-Limit", strconv.Itoa(fixtureQuota))
		headers.Set("X-Quota-Remaining", strconv.FormatInt(fixtureQuota-f.transferred.Load(), 10))
		headers.Set("X-Quota-Reset", f.resetAt.Format(time.RFC3339))
		if req.Method == http.MethodGet {
			body, _ = json.Marshal(map[string]string{"token": f.pass})
			f.proxyAuthorized.Store(true)
		}
	default:
		return nil, errOutsideTunnelFixture
	}
	headers.Set("Content-Type", "application/json")
	return &http.Response{
		Status: "200 OK", StatusCode: http.StatusOK, Header: headers,
		Body: io.NopCloser(strings.NewReader(string(body))), ContentLength: int64(len(body)), Request: req,
	}, nil
}

func fixtureMatch(candidate, expected string) bool {
	return subtle.ConstantTimeCompare([]byte(candidate), []byte(expected)) == 1
}

func fixtureCertificate() (tls.Certificate, *x509.CertPool, error) {
	var certificate tls.Certificate
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return certificate, nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return certificate, nil, err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: serial,
		NotBefore:    now.Add(-time.Minute), NotAfter: now.Add(24 * time.Hour),
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses: []net.IP{net.IPv4(127, 0, 0, 1)},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return certificate, nil, err
	}
	leaf, err := x509.ParseCertificate(der)
	if err != nil {
		return certificate, nil, err
	}
	roots := x509.NewCertPool()
	roots.AddCert(leaf)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key, Leaf: leaf}, roots, nil
}

func (f *tunnelFixture) serveConnect(w http.ResponseWriter, r *http.Request, originAddress string) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodConnect || r.Host != service.TunnelFixtureAuthority ||
		r.RequestURI != service.TunnelFixtureAuthority ||
		!fixtureMatch(r.Header.Get("Proxy-Authorization"), "Bearer "+f.pass) {
		http.Error(w, "Only the local tunnel test is allowed", http.StatusForbidden)
		return
	}

	origin, err := net.DialTimeout("unix", originAddress, 3*time.Second)
	if err != nil {
		http.Error(w, "Local test origin unavailable", http.StatusBadGateway)
		return
	}
	defer origin.Close()

	client, stream, err := http.NewResponseController(w).Hijack()
	if err != nil {
		return
	}
	defer client.Close()

	deadline := time.Now().Add(20 * time.Second)
	_ = client.SetDeadline(deadline)
	_ = origin.SetDeadline(deadline)
	if _, err := fmt.Fprint(stream, "HTTP/1.1 200 Connection Established\r\n\r\n"); err != nil || stream.Flush() != nil {
		return
	}

	done := make(chan struct{})
	go func() {
		_, _ = io.Copy(origin, stream.Reader)
		_ = origin.Close()
		close(done)
	}()
	_, _ = io.Copy(client, origin)
	_ = client.Close()
	<-done
}
