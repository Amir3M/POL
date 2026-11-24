//go:build poltunneltest

package mobile

import (
	"bytes"
	_ "embed"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/armanlife/arman-vpn-client/core/internal/service"
)

const fixturePayloadBytes = 256 * 1024

var fixturePayload = bytes.Repeat([]byte{'P'}, fixturePayloadBytes)

//go:embed tunnel_fixture.html
var fixturePage string

func (f *tunnelFixture) serveOrigin(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.Host != service.TunnelFixtureAuthority || r.URL.RawQuery != "" {
		http.Error(w, "Only the local tunnel test is allowed", http.StatusForbidden)
		return
	}
	w.Header().Set("X-POL-Tunnel-Proof", f.proof)
	switch {
	case r.Method == http.MethodGet && (r.URL.Path == "/" || r.URL.Path == "/pol-tunnel-test"):
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
		page := strings.NewReplacer("{{PROOF}}", f.proof, "{{BYTES}}", strconv.Itoa(fixturePayloadBytes)).Replace(fixturePage)
		if _, err := io.WriteString(w, page); err == nil {
			f.requests.Add(1)
		}
	case r.Method == http.MethodGet && r.URL.Path == "/download":
		if !f.reserveTransfer() {
			http.Error(w, "Fixture quota exhausted", http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", strconv.Itoa(fixturePayloadBytes))
		n, _ := w.Write(fixturePayload)
		f.bytesDown.Add(int64(n))
		f.transferred.Add(int64(n - fixturePayloadBytes))
	case r.Method == http.MethodPost && r.URL.Path == "/upload":
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, fixturePayloadBytes))
		if err != nil || !bytes.Equal(body, fixturePayload) {
			http.Error(w, "Upload did not match the fixture", http.StatusBadRequest)
			return
		}
		if !f.reserveTransfer() {
			http.Error(w, "Fixture quota exhausted", http.StatusTooManyRequests)
			return
		}
		f.bytesUp.Add(fixturePayloadBytes)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, strconv.Itoa(fixturePayloadBytes))
	default:
		http.NotFound(w, r)
	}
}

func (f *tunnelFixture) reserveTransfer() bool {
	for {
		used := f.transferred.Load()
		if used > fixtureQuota-fixturePayloadBytes {
			return false
		}
		if f.transferred.CompareAndSwap(used, used+fixturePayloadBytes) {
			return true
		}
	}
}
