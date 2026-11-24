package proxy

import (
	"context"
	"crypto/x509"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/guardian"
)

// The authorized Guardian client is tested separately. This test begins at
// the ProxyPassInfo boundary and runs the actual controller and H2 transport.
func TestControllerH2PassAndTrafficStages(t *testing.T) {
	const timeout = 5 * time.Second
	const upload, download = "fixture upload", "fixture download"
	pass := &guardian.ProxyPassInfo{
		RawToken: auditJWT(),
		Claims:   guardian.ProxyPassClaims{Exp: time.Now().Add(time.Hour).Unix()},
	}
	previousRoots, previousGoTLS := upstreamRoots.Load(), upstreamGoTLS.Load()
	t.Cleanup(func() {
		SetUpstreamRoots(previousRoots)
		upstreamGoTLS.Store(previousGoTLS)
	})
	upstreamGoTLS.Store(false)

	newController := func(t *testing.T, enableH2 bool, handler http.Handler) (*Controller, error) {
		t.Helper()
		server := httptest.NewUnstartedServer(handler)
		server.EnableHTTP2 = enableH2
		server.Config.ReadTimeout, server.Config.WriteTimeout = timeout, timeout
		server.StartTLS()
		t.Cleanup(server.Close)
		roots := x509.NewCertPool()
		roots.AddCert(server.Certificate())
		SetUpstreamRoots(roots)
		proxyURL, err := url.Parse(server.URL)
		if err != nil {
			t.Fatal(err)
		}
		controller, err := NewController(ControllerConfig{
			ProxyURL: proxyURL, Timeout: timeout, Pass: pass, Sessions: 1,
		})
		if controller != nil {
			t.Cleanup(func() { _ = controller.Close() })
		}
		return controller, err
	}

	t.Run("trusted TLS without H2", func(t *testing.T) {
		_, err := newController(t, false, http.NotFoundHandler())
		if !errors.Is(err, errProxyHTTP2Unavailable) {
			t.Fatalf("expected H2 negotiation failure, got %v", err)
		}
	})

	t.Run("H2 CONNECT and traffic", func(t *testing.T) {
		var authorizedRequests atomic.Int32
		controller, err := newController(t, true, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.ProtoMajor != 2 || r.Method != http.MethodConnect || r.Header.Get("Proxy-Authorization") != pass.BearerToken() {
				t.Error("fixture did not receive the pass on an H2 CONNECT")
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			authorizedRequests.Add(1)
			switch r.Host {
			case "refused.fixture.invalid:443":
				w.WriteHeader(http.StatusServiceUnavailable)
			case "empty.fixture.invalid:443":
				w.WriteHeader(http.StatusOK)
			case "transfer.fixture.invalid:443":
				w.WriteHeader(http.StatusOK)
				if err := http.NewResponseController(w).Flush(); err != nil {
					t.Errorf("flushing local CONNECT response: %v", err)
					return
				}
				body := make([]byte, len(upload))
				if _, err := io.ReadFull(r.Body, body); err != nil || string(body) != upload {
					t.Errorf("fixture did not receive the upload: %v", err)
					return
				}
				_, _ = io.WriteString(w, download)
			default:
				t.Error("unexpected fixture target")
				w.WriteHeader(http.StatusBadRequest)
			}
		}))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := controller.OpenTunnel("refused.fixture.invalid:443"); err == nil {
			t.Fatal("refused CONNECT unexpectedly opened a tunnel")
		} else {
			var failure *proxyConnectHTTPError
			if !errors.As(err, &failure) || failure.statusCode != http.StatusServiceUnavailable {
				t.Fatalf("expected HTTP rejection after H2, got %v", err)
			}
		}
		empty, err := controller.OpenTunnel("empty.fixture.invalid:443")
		if err != nil {
			t.Fatal(err)
		}
		defer empty.Close()
		if got, err := empty.Read(make([]byte, 1)); got != 0 || !errors.Is(err, io.EOF) {
			t.Fatalf("expected empty CONNECT stream, got %d bytes and %v", got, err)
		}
		if got := controller.trafficSinceReading.Load(); got != 0 {
			t.Fatalf("CONNECT negotiation counted as traffic: %d bytes", got)
		}

		stream, err := controller.OpenTunnel("transfer.fixture.invalid:443")
		if err != nil {
			t.Fatal(err)
		}
		defer stream.Close()
		ctx, cancel := context.WithTimeout(t.Context(), timeout)
		defer cancel()
		stop := context.AfterFunc(ctx, func() { _ = stream.Close() })
		defer stop()
		if _, err := io.WriteString(stream, upload); err != nil {
			t.Fatal(err)
		}
		body := make([]byte, len(download))
		if _, err := io.ReadFull(stream, body); err != nil || string(body) != download {
			t.Fatalf("controller did not receive the download: %v", err)
		}
		if got := controller.trafficSinceReading.Load(); got != int64(len(upload)+len(download)) {
			t.Fatalf("controller counted %d traffic bytes", got)
		}
		if got := authorizedRequests.Load(); got != 3 {
			t.Fatalf("expected 3 authorized CONNECT requests, got %d", got)
		}
	})
}
