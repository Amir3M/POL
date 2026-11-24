//go:build poltunneltest

package mobile

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	netproxy "golang.org/x/net/proxy"

	"github.com/armanlife/arman-vpn-client/core/internal/controlplane"
	"github.com/armanlife/arman-vpn-client/core/internal/service"
)

const fixtureURL = "http://" + service.TunnelFixtureAuthority

func TestTunnelFixtureUsesRealMobileSOCKS(t *testing.T) {
	root := t.TempDir()
	stale := filepath.Join(root, fixtureDirPrefix+"stale")
	if err := os.Mkdir(stale, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := StartTunnelTest(root, ""); err == nil {
		t.Fatal("fixture accepted a missing local session")
	}
	if err := RenewTunnelTest(); err == nil {
		t.Fatal("fixture renewed before it connected")
	}
	if err := StartTunnelTest(root, "synthetic-local-session-id"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(StopTunnelTest)
	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Fatal("a stale fixture directory survived startup")
	}
	if DashboardAddress() != "" {
		t.Fatal("the fixture unexpectedly opens the dashboard")
	}

	var status fixtureStatus
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); {
		status = readFixtureStatus(t)
		if status.Connected || status.FailureCode != "" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !status.SessionReady || !status.TokenRefreshed || !status.ProxyAuthorized || !status.Connected {
		t.Fatalf("fixture did not establish the local upstream: %s", TunnelTestStatus())
	}
	checkQuota(t, status, fixtureQuota)

	if _, err := TunConfig(1500); err != nil {
		t.Fatal(err)
	}
	address, user, password, err := running.OpenTunListener()
	if err != nil {
		t.Fatal(err)
	}
	dialer, err := netproxy.SOCKS5("tcp", address, &netproxy.Auth{User: user, Password: password}, &net.Dialer{Timeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	dial := dialer.(netproxy.ContextDialer).DialContext
	client := &http.Client{
		Timeout:       3 * time.Second,
		Transport:     &http.Transport{DialContext: dial},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	defer client.CloseIdleConnections()

	get := func(path string) (*http.Response, []byte) {
		t.Helper()
		response, err := client.Get(fixtureURL + path)
		if err != nil {
			t.Fatal(err)
		}
		body := readFixtureResponse(t, response, http.StatusOK)
		return response, body
	}

	page, body := get("/")
	proof := page.Header.Get("X-POL-Tunnel-Proof")
	if proof == "" || !bytes.Contains(body, []byte(proof)) || !bytes.Contains(body, []byte("POL tunnel fixture response")) {
		t.Fatal("the external-style HTTP request did not reach the fixture origin")
	}
	download, data := get("/download")
	if download.Header.Get("X-POL-Tunnel-Proof") != proof || !bytes.Equal(data, fixturePayload) {
		t.Fatal("fixture download did not match expected data")
	}
	bad, err := client.Post(fixtureURL+"/upload", "application/octet-stream", strings.NewReader("not the test data"))
	if err != nil {
		t.Fatal(err)
	}
	readFixtureResponse(t, bad, http.StatusBadRequest)
	upload, err := client.Post(fixtureURL+"/upload", "application/octet-stream", bytes.NewReader(fixturePayload))
	if err != nil {
		t.Fatal(err)
	}
	if string(readFixtureResponse(t, upload, http.StatusOK)) != "262144" {
		t.Fatal("fixture upload was not validated")
	}
	status = readFixtureStatus(t)
	if status.Requests != 1 || status.BytesUp != fixturePayloadBytes || status.BytesDown != fixturePayloadBytes {
		t.Fatalf("wrong validated transfer counters: %s", TunnelTestStatus())
	}
	checkQuota(t, status, fixtureQuota-2*fixturePayloadBytes)

	if err := RenewTunnelTest(); err != nil {
		t.Fatal(err)
	}
	status = readFixtureStatus(t)
	if !status.SessionRenewed || status.Renewals != 1 || !status.Connected {
		t.Fatalf("fixture did not renew in place: %s", TunnelTestStatus())
	}
	reused := false
	ctx := httptrace.WithClientTrace(context.Background(), &httptrace.ClientTrace{
		GotConn: func(info httptrace.GotConnInfo) { reused = info.Reused },
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fixtureURL+"/", nil)
	if err != nil {
		t.Fatal(err)
	}
	after, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	readFixtureResponse(t, after, http.StatusOK)
	if !reused || after.Header.Get("X-POL-Tunnel-Proof") != proof {
		t.Fatal("the existing fixture HTTP connection did not survive renewal")
	}

	for _, rejected := range []string{"192.0.2.2:8080", "192.0.2.1:443", "127.0.0.1:8080", "example.invalid:443"} {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		conn, err := dial(ctx, "tcp", rejected)
		cancel()
		if err == nil {
			conn.Close()
			t.Fatalf("fixture allowed out-of-scope target %s", rejected)
		}
	}
	checkFixtureRejectsHTTPAndUDP(t, address, user, password)
	checkFixtureRejectsProxyRequests(t, activeFixture.Load())
	checkFixtureRejectsUnknownControlPlane(t)

	StopTunnelTest()
	if readFixtureStatus(t).Connected {
		t.Fatal("fixture still reports connected after stop")
	}
	if entries, err := os.ReadDir(root); err != nil || len(entries) != 0 {
		t.Fatalf("fixture cache was not cleared: %d entries, %v", len(entries), err)
	}
	if conn, err := net.DialTimeout("tcp", address, time.Second); err == nil {
		conn.Close()
		t.Fatal("fixture TUN listener stayed open after stop")
	}
}

func TestTunnelFixtureControlPlaneFailsClosed(t *testing.T) {
	checkFixtureRejectsUnknownControlPlane(t)
}

func checkFixtureRejectsUnknownControlPlane(t *testing.T) {
	t.Helper()
	for _, url := range []string{
		"https://example.invalid/",
		"https://api.accounts.firefox.com/v1/oauth/token",
		"https://" + fixtureGuardianHost + "/unsupported",
	} {
		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			t.Fatal(err)
		}
		response, err := controlplane.Do(req)
		if response != nil {
			response.Body.Close()
		}
		if !errors.Is(err, errOutsideTunnelFixture) {
			t.Fatalf("the fixture did not explicitly reject %s: %v", url, err)
		}
	}
}

func checkFixtureRejectsProxyRequests(t *testing.T, f *tunnelFixture) {
	t.Helper()
	roots := x509.NewCertPool()
	roots.AddCert(f.upstream.TLSConfig.Certificates[0].Leaf)
	clientTLS := &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}
	for _, rejected := range []struct{ target, pass string }{
		{service.TunnelFixtureAuthority, "invalid-fixture-pass"},
		{"192.0.2.2:8080", f.pass},
	} {
		conn, err := tls.DialWithDialer(&net.Dialer{Timeout: time.Second}, "tcp4", f.upstream.Addr, clientTLS)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		if err := conn.SetDeadline(time.Now().Add(time.Second)); err != nil {
			t.Fatal(err)
		}
		if _, err := fmt.Fprintf(conn, "CONNECT %s HTTP/1.1\r\nHost: %s\r\nProxy-Authorization: Bearer %s\r\n\r\n",
			rejected.target, rejected.target, rejected.pass); err != nil {
			t.Fatal("could not write local fixture CONNECT")
		}
		response, err := http.ReadResponse(bufio.NewReader(conn), &http.Request{Method: http.MethodConnect})
		if err != nil {
			t.Fatal("could not read local fixture CONNECT response")
		}
		readFixtureResponse(t, response, http.StatusForbidden)
	}
}

func readFixtureStatus(t *testing.T) fixtureStatus {
	t.Helper()
	var status fixtureStatus
	if err := json.Unmarshal([]byte(TunnelTestStatus()), &status); err != nil {
		t.Fatal(err)
	}
	return status
}

func checkQuota(t *testing.T, status fixtureStatus, remaining int64) {
	t.Helper()
	if status.QuotaLimit == nil || *status.QuotaLimit != fixtureQuota ||
		status.QuotaRemaining == nil || *status.QuotaRemaining != remaining {
		t.Fatalf("quota did not match the synthetic service response: %s", TunnelTestStatus())
	}
}

func readFixtureResponse(t *testing.T, response *http.Response, want int) []byte {
	t.Helper()
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != want || response.Header.Get("Cache-Control") != "no-store" {
		t.Fatalf("status %d (want %d), cache control %q", response.StatusCode, want, response.Header.Get("Cache-Control"))
	}
	return body
}

func checkFixtureRejectsHTTPAndUDP(t *testing.T, address, user, password string) {
	t.Helper()
	httpConn, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer httpConn.Close()
	if err := httpConn.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(httpConn, "CONNECT "+service.TunnelFixtureAuthority+" HTTP/1.1\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(httpConn, make([]byte, 1)); err == nil {
		t.Fatal("the fixture TUN listener accepted an HTTP proxy request")
	}

	udpConn, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer udpConn.Close()
	if err := udpConn.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	exchange := func(out []byte, lenIn int) []byte {
		t.Helper()
		if _, err := udpConn.Write(out); err != nil {
			t.Fatal(err)
		}
		in := make([]byte, lenIn)
		if _, err := io.ReadFull(udpConn, in); err != nil {
			t.Fatal(err)
		}
		return in
	}
	if reply := exchange([]byte{5, 1, 2}, 2); !bytes.Equal(reply, []byte{5, 2}) {
		t.Fatal("fixture did not require SOCKS5 authentication")
	}
	auth := append([]byte{1, byte(len(user))}, user...)
	auth = append(append(auth, byte(len(password))), password...)
	if reply := exchange(auth, 2); !bytes.Equal(reply, []byte{1, 0}) {
		t.Fatal("fixture rejected its local SOCKS5 credentials")
	}
	if reply := exchange([]byte{5, 3, 0, 1, 192, 0, 2, 1, 0x1f, 0x90}, 10); reply[1] != 7 {
		t.Fatal("fixture did not reject the UDP associate command")
	}
}
