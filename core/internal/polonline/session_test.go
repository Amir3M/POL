package polonline

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
	"github.com/armanlife/arman-vpn-client/core/internal/guardian"
)

type memoryStore struct {
	blob string
	err  error
}

func (m *memoryStore) Load() (string, error) { return m.blob, nil }
func (m *memoryStore) Save(blob string) error {
	if m.err != nil {
		return m.err
	}
	m.blob = blob
	return nil
}
func (m *memoryStore) Clear() error {
	m.blob = ""
	return nil
}

type fixtureOAuth struct {
	oauthClient
	exchange func() (*fxa.TokenResponse, error)
	refresh  func(string) (*fxa.TokenResponse, error)
}

func (f fixtureOAuth) Exchange(context.Context, *fxa.POLAuthorization, string) (*fxa.TokenResponse, error) {
	return f.exchange()
}
func (f fixtureOAuth) Refresh(_ context.Context, token string) (*fxa.TokenResponse, error) {
	return f.refresh(token)
}

type fixtureGuardian func(string) (*guardian.ProxyPassInfo, error)

func (f fixtureGuardian) FetchProxyPass(_ context.Context, token string) (*guardian.ProxyPassInfo, error) {
	return f(token)
}

func fixtureConfig() Config {
	return Config{
		OAuth: fxa.POLClientConfig{
			ClientID:              "pol-test",
			AuthorizationEndpoint: "https://identity.invalid/authorization",
			TokenEndpoint:         "https://identity.invalid/token",
			RedirectURI:           "com.polvpn.app.debug:/callback",
			Scopes:                []string{"https://identity.invalid/vpn"},
		},
		GuardianOrigin: "https://guardian.invalid",
	}
}

func TestSessionRestoresRefreshesAndClearsCredentials(t *testing.T) {
	ctx := t.Context()
	store := new(memoryStore)
	config := fixtureConfig()
	now := time.Now()
	signedIn, err := NewSession(config, store)
	if err != nil {
		t.Fatal(err)
	}
	signedIn.now = func() time.Time { return now }
	signedIn.oauth = fixtureOAuth{oauthClient: signedIn.oauth, exchange: func() (*fxa.TokenResponse, error) {
		return &fxa.TokenResponse{AccessToken: "fixture-access", RefreshToken: "fixture-refresh", ExpiresIn: 3600}, nil
	}}
	if _, err := signedIn.BeginSignIn(); err != nil {
		t.Fatal(err)
	}
	if err := signedIn.CompleteSignIn(ctx, "synthetic callback"); err != nil {
		t.Fatal(err)
	}
	if err := signedIn.CompleteSignIn(ctx, "synthetic callback"); err == nil {
		t.Fatal("accepted a replayed callback")
	}
	restored, err := NewSession(config, store)
	if err != nil {
		t.Fatal(err)
	}
	restored.now = func() time.Time { return now.Add(2 * time.Hour) }
	if ok, err := restored.Restore(); !ok || err != nil {
		t.Fatal("could not restore fixture session")
	}
	restored.oauth = fixtureOAuth{refresh: func(refresh string) (*fxa.TokenResponse, error) {
		if refresh != "fixture-refresh" {
			t.Fatal("refresh did not use the stored credential")
		}
		return &fxa.TokenResponse{AccessToken: "rotated-access", RefreshToken: "rotated-refresh", ExpiresIn: 3600}, nil
	}}
	restored.guardian = fixtureGuardian(func(access string) (*guardian.ProxyPassInfo, error) {
		if access != "rotated-access" {
			t.Fatal("Guardian did not receive the refreshed credential")
		}
		if status := restored.Snapshot(); status.Stage != "guardian" || status.HTTPStatus != 0 {
			t.Fatalf("unexpected in-flight stage: %+v", status)
		}
		return &guardian.ProxyPassInfo{RawToken: "fixture-proxy-pass", Usage: &guardian.ProxyUsage{Limit: 25, Remaining: 10}}, nil
	})
	if _, err := restored.ProxyPass(ctx); err != nil {
		t.Fatal(err)
	}
	status := restored.Snapshot()
	if status.Stage != "proxy_pass" || status.HTTPStatus != 200 ||
		status.Quota == nil || status.Quota.Remaining == nil || *status.Quota.Remaining != 10 {
		t.Fatalf("unexpected authorized stage: %+v", status)
	}
	encoded, err := json.Marshal(status)
	if err != nil || strings.Contains(string(encoded), "fixture") || strings.Contains(string(encoded), "rotated") {
		t.Fatal("diagnostics contain fixture credentials")
	}
	if !strings.Contains(store.blob, "rotated-refresh") {
		t.Fatal("rotated credential did not reach the store")
	}
	other := config
	other.GuardianOrigin = "https://different-guardian.invalid"
	different, err := NewSession(other, store)
	if err != nil {
		t.Fatal(err)
	}
	if ok, err := different.Restore(); ok || err == nil {
		t.Fatal("restored a credential across registrations")
	}
	if err := restored.Logout(); err != nil || store.blob != "" {
		t.Fatal("logout left stored credentials")
	}
	if _, err := restored.ProxyPass(ctx); err == nil || restored.Snapshot().Reason != "session_required" {
		t.Fatal("logout did not gate subsequent Guardian calls")
	}
}

func TestSessionRejectsInvalidConfigAndReportsDirectFailures(t *testing.T) {
	if _, err := NewSession(Config{}, new(memoryStore)); err == nil {
		t.Fatal("accepted an empty provider configuration")
	}
	s, err := NewSession(fixtureConfig(), new(memoryStore))
	if err != nil {
		t.Fatal(err)
	}
	s.tokens = &fxa.SavedTokens{AccessToken: "mock-access", RefreshToken: "mock-refresh", ObtainedAt: time.Now(), ExpiresIn: 3600}
	for _, tc := range []struct {
		name   string
		err    error
		stage  string
		reason string
		status int
	}{
		{"no HTTP", &guardian.DirectError{Kind: guardian.DirectNoHTTPResponse}, "guardian", "request_failed", 0},
		{"redirect", &guardian.DirectError{Kind: guardian.DirectHTTPRejected, StatusCode: 302}, "guardian", "redirect_refused", 302},
		{"entitlement", &guardian.DirectError{Kind: guardian.DirectHTTPRejected, StatusCode: 403}, "guardian", "not_entitled", 403},
		{"region", &guardian.DirectError{Kind: guardian.DirectHTTPRejected, StatusCode: 451}, "guardian", "region_unavailable", 451},
		{"malformed pass", &guardian.DirectError{Kind: guardian.DirectInvalidProxyPass, StatusCode: 200}, "proxy_pass", "invalid_response", 200},
		{"unexpected error", errors.New("opaque raw-response details"), "guardian", "request_failed", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s.guardian = fixtureGuardian(func(string) (*guardian.ProxyPassInfo, error) { return nil, tc.err })
			_, err := s.ProxyPass(t.Context())
			status := s.Snapshot()
			if err == nil || strings.Contains(err.Error(), "opaque") || status.Stage != tc.stage ||
				status.Reason != tc.reason || status.HTTPStatus != tc.status || status.Quota != nil {
				t.Fatalf("unexpected diagnostics: %+v", status)
			}
		})
	}
}

func TestSessionStopsBeforeGuardianWhenRefreshCannotBeStored(t *testing.T) {
	store := &memoryStore{err: errors.New("raw platform error")}
	s, err := NewSession(fixtureConfig(), store)
	if err != nil {
		t.Fatal(err)
	}
	s.tokens = &fxa.SavedTokens{RefreshToken: "mock-refresh", ObtainedAt: time.Now().Add(-time.Hour), ExpiresIn: 60}
	s.oauth = fixtureOAuth{refresh: func(string) (*fxa.TokenResponse, error) {
		return &fxa.TokenResponse{AccessToken: "next-access", RefreshToken: "next-refresh", ExpiresIn: 3600}, nil
	}}
	s.guardian = fixtureGuardian(func(string) (*guardian.ProxyPassInfo, error) {
		t.Fatal("a session with an unpersisted refresh reached Guardian")
		return nil, nil
	})
	_, err = s.ProxyPass(t.Context())
	if err == nil || strings.Contains(err.Error(), "platform") || s.Snapshot().Reason != "session_storage" || s.tokens != nil {
		t.Fatal("credential persistence failure did not close the session")
	}
}

func TestUnlimitedQuotaExportContainsNoInventedByteLimits(t *testing.T) {
	s, err := NewSession(fixtureConfig(), new(memoryStore))
	if err != nil {
		t.Fatal(err)
	}
	s.record("proxy_pass", 200, "", &guardian.ProxyUsage{Unlimited: true})
	blob, err := json.Marshal(s.Snapshot().Quota)
	if err != nil || string(blob) != `{"unlimited":true}` {
		t.Fatalf("unexpected unlimited quota schema: %s", blob)
	}
}
