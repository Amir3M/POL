package guardian

import (
	"context"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const directFixtureAccess = "local-fixture-access-token"

func TestDirectClientRequiresAnHTTPSOrigin(t *testing.T) {
	for _, origin := range []string{
		"", "http://guardian.invalid", "https://", "https:///guardian.invalid",
		"https://user@guardian.invalid", "https://guardian.invalid/private",
		"https://guardian.invalid/%2f", "https://guardian.invalid/?a=1",
		"https://guardian.invalid/?", "https://guardian.invalid/#", "https://guardian.invalid#secret",
		"https://guardian.invalid:0", "https://guardian.invalid:65536", "https://guardian.invalid:",
	} {
		t.Run(origin, func(t *testing.T) {
			if _, err := NewDirectClient(origin); err == nil {
				t.Fatalf("invalid origin accepted: %q", origin)
			}
		})
	}
	for _, origin := range []string{"https://guardian.invalid", "https://guardian.invalid/", "https://[::1]:443"} {
		client, err := NewDirectClient(origin)
		if err != nil {
			t.Fatal(err)
		}
		if transport := client.client.Transport.(*http.Transport); transport.Proxy != nil {
			t.Fatal("the direct transport allows a proxy")
		}
		if !strings.HasSuffix(client.tokenURL, directTokenPath) {
			t.Fatal("the client did not set the canonical token path")
		}
	}
}

func TestDirectClientFetchesPassAndQuotaOverTLS(t *testing.T) {
	var requests atomic.Int64
	client := directFixtureClient(t, func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.URL.RequestURI() != directTokenPath || r.Header.Get("Authorization") != "Bearer "+directFixtureAccess {
			t.Error("incorrect fixture destination or bearer")
		}
		if r.UserAgent() != "POL-VPN" {
			t.Error("request does not identify the POL client")
		}
		switch r.Method {
		case http.MethodGet:
			writeDirectFixtureQuota(w, "120")
			fmt.Fprint(w, directFixturePass(time.Now().Add(time.Hour)))
		case http.MethodHead:
			w.Header().Set("X-Quota-Unlimited", "true")
		default:
			t.Errorf("unexpected request method %s", r.Method)
		}
	})
	pass, err := client.FetchProxyPass(t.Context(), directFixtureAccess)
	if err != nil {
		t.Fatal(err)
	}
	if pass.RawToken == "" || pass.Usage == nil || pass.Usage.Limit != 1000 || pass.Usage.Remaining != 120 {
		t.Fatal("the fixture pass did not retain its reported finite quota")
	}
	usage, err := client.FetchProxyUsage(t.Context(), directFixtureAccess)
	if err != nil || usage == nil || !usage.Unlimited {
		t.Fatalf("unlimited quota not recognized: %+v, %v", usage, err)
	}
	if requests.Load() != 2 {
		t.Errorf("expected exactly one GET and one HEAD, got %d requests", requests.Load())
	}
}

func TestDirectClientClassifiesDenialsWithoutResponseBodies(t *testing.T) {
	for _, tc := range []struct {
		code int
		kind error
	}{
		{http.StatusUnauthorized, ErrTokenInvalid},
		{http.StatusForbidden, ErrNotEntitled},
		{http.StatusTooManyRequests, ErrQuotaExceeded},
		{http.StatusUnavailableForLegalReasons, ErrRegionUnavailable},
	} {
		t.Run(http.StatusText(tc.code), func(t *testing.T) {
			var requests atomic.Int64
			client := directFixtureClient(t, func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if r.URL.RequestURI() != directTokenPath {
					t.Errorf("request used a noncanonical path: %q", r.URL.RequestURI())
				}
				if tc.code == http.StatusTooManyRequests {
					writeDirectFixtureQuota(w, "0")
					w.Header().Set("Retry-After", "30")
				}
				w.WriteHeader(tc.code)
				fmt.Fprint(w, "private-response-marker")
			})

			for _, result := range []error{
				fetchDirectFixturePassError(t, client),
				fetchDirectFixtureUsageError(t, client),
			} {
				failure := checkDirectFailure(t, result, DirectHTTPRejected, tc.code)
				if !errors.Is(failure, tc.kind) || strings.Contains(failure.Error(), "private-response-marker") {
					t.Fatal("direct Guardian denial was misclassified or exposed its body")
				}
				if tc.code == http.StatusTooManyRequests &&
					(failure.RetryAfter != 30*time.Second || failure.Usage == nil || !failure.Usage.Exhausted()) {
					t.Fatal("quota denial did not retain the reported exhausted quota and retry delay")
				}
			}
			if requests.Load() != 2 {
				t.Fatalf("a denial triggered an unexpected retry or route: %d requests", requests.Load())
			}
		})
	}
}

func TestDirectClientDoesNotForwardBearerAcrossRedirect(t *testing.T) {
	var targetRequests atomic.Int64
	target := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		targetRequests.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(target.Close)

	for _, route := range []string{"/recovery", target.URL + "/capture"} {
		t.Run(route, func(t *testing.T) {
			var originalRequests atomic.Int64
			client := directFixtureClient(t, func(w http.ResponseWriter, r *http.Request) {
				originalRequests.Add(1)
				http.Redirect(w, r, route, http.StatusTemporaryRedirect)
			})

			checkDirectFailure(t, fetchDirectFixturePassError(t, client), DirectHTTPRejected, http.StatusTemporaryRedirect)
			if originalRequests.Load() != 1 || targetRequests.Load() != 0 {
				t.Fatal("the bearer request was redirected")
			}
		})
	}
}

func TestDirectClientDistinguishesTransportAndInvalidResponses(t *testing.T) {
	valid := directFixturePass(time.Now().Add(time.Hour))
	for _, tc := range []struct {
		name string
		body string
	}{
		{"malformed", `{"token":"private-response-marker"}`},
		{"unsigned", strings.Replace(valid, ".local", ".", 1)},
		{"invalid bearer", strings.Replace(valid, ".local", `.local\nprivate`, 1)},
		{"expired", directFixturePass(time.Now().Add(-time.Minute))},
		{"oversized", strings.Repeat(" ", maxDirectPass+1)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := directFixtureClient(t, func(w http.ResponseWriter, _ *http.Request) {
				fmt.Fprint(w, tc.body)
			})
			checkDirectFailure(t, fetchDirectFixturePassError(t, client), DirectInvalidProxyPass, http.StatusOK)
			checkDirectFailure(t, fetchDirectFixtureUsageError(t, client), DirectInvalidQuota, http.StatusOK)
		})
	}

	var requests atomic.Int64
	server := httptest.NewTLSServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		requests.Add(1)
	}))
	t.Cleanup(server.Close)
	client, err := NewDirectClient(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	checkDirectFailure(t, fetchDirectFixturePassError(t, client), DirectNoHTTPResponse, 0)
	if requests.Load() != 0 {
		t.Fatal("the client sent a request with an untrusted server certificate")
	}

	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	_, err = client.FetchProxyPass(ctx, directFixtureAccess)
	checkDirectFailure(t, err, DirectNoHTTPResponse, 0)
	if !errors.Is(err, context.Canceled) {
		t.Fatal("cancellation was not preserved")
	}
	_, err = client.FetchProxyPass(t.Context(), "invalid bearer\nprivate")
	checkDirectFailure(t, err, DirectInvalidAccessToken, 0)
}

func directFixtureClient(t *testing.T, handler http.HandlerFunc) *DirectClient {
	t.Helper()
	server := httptest.NewTLSServer(handler)
	t.Cleanup(server.Close)
	roots := x509.NewCertPool()
	roots.AddCert(server.Certificate())
	client, err := newDirectClient(server.URL, roots)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(client.client.CloseIdleConnections)
	return client
}

func directFixturePass(expiry time.Time) string {
	claims := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf(`{"exp":%d}`, expiry.Unix())))
	payload, _ := json.Marshal(proxyPassResponse{Token: "fixture." + claims + ".local"})
	return string(payload)
}

func writeDirectFixtureQuota(w http.ResponseWriter, remaining string) {
	w.Header().Set("X-Quota-Limit", "1000")
	w.Header().Set("X-Quota-Remaining", remaining)
	w.Header().Set("X-Quota-Reset", time.Now().Add(time.Hour).UTC().Format(time.RFC3339))
}

func fetchDirectFixturePassError(t *testing.T, client *DirectClient) error {
	t.Helper()
	if pass, err := client.FetchProxyPass(t.Context(), directFixtureAccess); pass == nil && err != nil {
		return err
	}
	t.Fatal("expected the direct pass request to fail")
	return nil
}

func fetchDirectFixtureUsageError(t *testing.T, client *DirectClient) error {
	t.Helper()
	if usage, err := client.FetchProxyUsage(t.Context(), directFixtureAccess); usage == nil && err != nil {
		return err
	}
	t.Fatal("expected the direct quota request to fail")
	return nil
}

func checkDirectFailure(t *testing.T, err error, kind DirectErrorKind, status int) *DirectError {
	t.Helper()
	var failure *DirectError
	if !errors.As(err, &failure) || failure.Kind != kind || failure.StatusCode != status {
		t.Fatalf("error %v, want %s with HTTP %d", err, kind, status)
	}
	return failure
}
