package service

import (
	"errors"
	"io"
	"net"
	"net/netip"
	"testing"
	"time"
)

func TestSharedProxySubnetRestrictsLAN(t *testing.T) {
	ip, subnet, err := sharedProxySubnet("192.168.43.1", 24)
	if err != nil || ip != netip.MustParseAddr("192.168.43.1") ||
		!subnet.Contains(netip.MustParseAddr("192.168.43.2")) ||
		subnet.Contains(netip.MustParseAddr("192.168.44.2")) {
		t.Fatalf("wrong private scope: %v %v %v", ip, subnet, err)
	}
	for _, ip := range []string{"0.0.0.0", "127.0.0.1", "8.8.8.8", "169.254.1.1", "fd00::1"} {
		if _, _, err := sharedProxySubnet(ip, 24); err == nil {
			t.Errorf("accepted local bind address %s", ip)
		}
	}
	for _, bits := range []int{-1, 0, 32, 33} {
		if _, _, err := sharedProxySubnet("192.168.43.1", bits); err == nil {
			t.Errorf("accepted LAN prefix size %d", bits)
		}
	}
}

func TestSharedProxyClosesLiveAndLateConnections(t *testing.T) {
	a := &sharedProxyAccess{active: make(map[net.Conn]struct{})}
	for range 2 {
		socket, peer := net.Pipe()
		t.Cleanup(func() { _ = peer.Close() })
		if _, ok := a.track(socket); !ok {
			t.Fatal("an open share declined a connection")
		}
		t.Cleanup(func() {
			_ = peer.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
			var buf [1]byte
			if _, err := peer.Read(buf[:]); err == nil {
				t.Error("shared connection still open")
			} else if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
				t.Error("shared connection did not close promptly")
			}
		})
	}
	a.close()
	late, peer := net.Pipe()
	defer peer.Close()
	if _, ok := a.track(late); ok {
		t.Fatal("accepted a tunnel from a closed credential generation")
	}
	a.daemon = &Daemon{}
	if _, err := a.OpenTunnel("example.com:443"); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("open after shutdown: %v", err)
	}
}

func TestSharedProxyBlocksLocalTargets(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "0.0.0.0", "10.0.0.23", "169.254.169.254", "::1", "fd00::1", "localhost", "x.localhost", "device.local."} {
		if sharedProxyTarget(host) {
			t.Errorf("accepted local destination %q", host)
		}
	}
	if !sharedProxyTarget("example.com") || !sharedProxyTarget("1.1.1.1") {
		t.Fatal("rejected public targets")
	}
}

func TestSharedProxyRequiresSOCKSAuthentication(t *testing.T) {
	d := &Daemon{}
	session := d.newSharedProxyAccess(SharedProxyInfo{Username: "share", Password: "temporary"})
	defer session.close()
	server, client := net.Pipe()
	defer client.Close()
	_ = client.SetDeadline(time.Now().Add(time.Second))
	go session.server.ServeConn(server)

	if _, err := client.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	var reply [2]byte
	if _, err := io.ReadFull(client, reply[:]); err != nil {
		t.Fatal(err)
	}
	if reply != [2]byte{5, 0xff} {
		t.Fatalf("accepted a client that offered only no-auth: %v", reply)
	}
}
