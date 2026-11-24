package fxa

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func polTestConfig(base string) POLClientConfig {
	return POLClientConfig{
		ClientID:              "local-pol-public-client",
		AuthorizationEndpoint: base + "/authorize",
		TokenEndpoint:         base + "/token",
		RedirectURI:           "com.polvpn.app:/oauth2redirect",
		Scopes:                []string{"profile", "test.vpn"},
	}
}

func TestPOLOAuthExchangeAndRefresh(t *testing.T) {
	requests := make(chan url.Values, 3)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/token" ||
			r.Header.Get("Content-Type") != "application/x-www-form-urlencoded" || r.ParseForm() != nil {
			t.Error("Expected a POST form at the registered token endpoint")
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		requests <- r.PostForm
		switch {
		case r.PostForm.Get("grant_type") == "authorization_code":
			fmt.Fprint(w, `{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600,"scope":"profile test.vpn","token_type":"Bearer"}`)
		case r.PostForm.Get("refresh_token") == "fixture-refresh":
			fmt.Fprint(w, `{"access_token":"fixture-renewed","refresh_token":"fixture-rotated","expires_in":1800,"token_type":"bearer"}`)
		default:
			fmt.Fprint(w, `{"access_token":"fixture-renewed-again","expires_in":1800,"token_type":"bearer"}`)
		}
	}))
	defer server.Close()
	config := polTestConfig(server.URL)
	client, err := newPOLClient(config, server.Client().Transport)
	if err != nil {
		t.Fatal(err)
	}
	attempt, err := client.BeginAuthorization()
	if err != nil {
		t.Fatal(err)
	}
	secondAttempt, err := client.BeginAuthorization()
	if err != nil || attempt.URL() == secondAttempt.URL() {
		t.Fatalf("Authorization attempts should be independent: %v", err)
	}
	requestURL, err := url.Parse(attempt.URL())
	if err != nil {
		t.Fatal(err)
	}
	authorization := requestURL.Query()
	if requestURL.Scheme+"://"+requestURL.Host+requestURL.Path != config.AuthorizationEndpoint ||
		authorization.Get("client_id") != config.ClientID ||
		authorization.Get("redirect_uri") != config.RedirectURI ||
		authorization.Get("response_type") != "code" || authorization.Get("scope") != "profile test.vpn" ||
		authorization.Get("code_challenge_method") != "S256" || len(authorization.Get("state")) != 43 ||
		authorization.Has("client_secret") || authorization.Has("code_verifier") {
		t.Fatal("Unexpected authorization request")
	}

	callback := config.RedirectURI + "?" + url.Values{
		"code": {"fixture-code"}, "state": {authorization.Get("state")},
	}.Encode()
	token, err := client.Exchange(t.Context(), attempt, callback)
	if err != nil {
		t.Fatal(err)
	}
	if token.AccessToken != "fixture-access" || token.RefreshToken != "fixture-refresh" ||
		token.Scope != "profile test.vpn" || token.ExpiresIn != 3600 {
		t.Fatal("Expected approved initial authentication tokens")
	}
	exchange := <-requests
	challenge := sha256.Sum256([]byte(exchange.Get("code_verifier")))
	if exchange.Get("client_id") != config.ClientID || exchange.Get("grant_type") != "authorization_code" ||
		exchange.Get("redirect_uri") != config.RedirectURI || exchange.Get("code") != "fixture-code" ||
		base64.RawURLEncoding.EncodeToString(challenge[:]) != authorization.Get("code_challenge") ||
		exchange.Has("client_secret") {
		t.Fatal("Token exchange does not match the registered public client and PKCE challenge")
	}

	renewed, err := client.Refresh(t.Context(), token.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	if renewed.AccessToken != "fixture-renewed" || renewed.RefreshToken != "fixture-rotated" || renewed.Scope != "" {
		t.Fatal("Expected rotated refresh token with omitted scope preserved")
	}
	renewAgain, err := client.Refresh(t.Context(), renewed.RefreshToken)
	if err != nil || renewAgain.RefreshToken != renewed.RefreshToken {
		t.Fatalf("Expected existing refresh token when the provider omits a replacement: %v", err)
	}
	for _, expected := range []string{token.RefreshToken, renewed.RefreshToken} {
		form := <-requests
		if form.Get("client_id") != config.ClientID || form.Get("grant_type") != "refresh_token" ||
			form.Get("refresh_token") != expected || form.Has("client_secret") || form.Has("scope") {
			t.Fatal("Unexpected public-client refresh request")
		}
	}
}

func TestPOLOAuthCallbackValidation(t *testing.T) {
	var exchanges atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		exchanges.Add(1)
		fmt.Fprint(w, `{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600,"token_type":"bearer"}`)
	}))
	defer server.Close()
	config := polTestConfig(server.URL)
	client, err := newPOLClient(config, server.Client().Transport)
	if err != nil {
		t.Fatal(err)
	}
	attempt, err := client.BeginAuthorization()
	if err != nil {
		t.Fatal(err)
	}
	state := attempt.transaction.state
	validCallback := config.RedirectURI + "?code=fixture-code&state=" + state
	for _, callback := range []string{
		strings.Replace(validCallback, "com.polvpn.app:", "com.other.app:", 1),
		strings.Replace(validCallback, "/oauth2redirect", "/oauth2redirect/", 1),
		config.RedirectURI + "?code=fixture-code&state=wrong",
		validCallback + "&state=" + state,
		validCallback + "#fragment",
		config.RedirectURI + "?" + strings.Repeat("a", polMaxCallback),
	} {
		if _, err := client.Exchange(t.Context(), attempt, callback); !errors.Is(err, ErrPOLCallback) {
			t.Fatalf("Expected callback validation error, got %v", err)
		}
	}
	other, err := newPOLClient(config, server.Client().Transport)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := other.Exchange(t.Context(), attempt, validCallback); !errors.Is(err, ErrPOLCallback) {
		t.Fatalf("Expected rejection when using another client instance, got %v", err)
	}
	if exchanges.Load() != 0 {
		t.Fatal("Invalid callbacks must never reach the token endpoint")
	}

	copyOfAttempt := *attempt
	var both sync.WaitGroup
	results := make(chan error, 2)
	for _, candidate := range []*POLAuthorization{attempt, &copyOfAttempt} {
		both.Go(func() {
			_, err := client.Exchange(t.Context(), candidate, validCallback)
			results <- err
		})
	}
	both.Wait()
	close(results)
	var passed, replayed int
	for err := range results {
		switch {
		case err == nil:
			passed++
		case errors.Is(err, ErrPOLAuthorizationUsed):
			replayed++
		default:
			t.Fatalf("Unexpected callback result: %v", err)
		}
	}
	if passed != 1 || replayed != 1 || exchanges.Load() != 1 {
		t.Fatal("A state must authorize exactly one HTTPS exchange")
	}

	expired, err := client.BeginAuthorization()
	if err != nil {
		t.Fatal(err)
	}
	expired.transaction.expiresAt = time.Now().Add(-time.Minute)
	if _, err := client.Exchange(t.Context(), expired, config.RedirectURI+"?code=fixture-code&state="+expired.transaction.state); !errors.Is(err, ErrPOLAuthorizationOld) {
		t.Fatalf("Expected expired callback to fail safely, got %v", err)
	}

	denied, err := client.BeginAuthorization()
	if err != nil {
		t.Fatal(err)
	}
	callback := config.RedirectURI + "?error=access_denied&error_description=private&state=" + denied.transaction.state
	_, err = client.Exchange(t.Context(), denied, callback)
	var oauthErr *POLOAuthError
	if !errors.As(err, &oauthErr) || oauthErr.Kind != POLOAuthDenied || oauthErr.HTTPStatus != 0 ||
		strings.Contains(err.Error(), "private") {
		t.Fatalf("Expected sanitized provider denial, got %v", err)
	}
	if _, err := client.Exchange(t.Context(), denied, callback); !errors.Is(err, ErrPOLAuthorizationUsed) {
		t.Fatalf("Expected the denied callback to consume state, got %v", err)
	}
}

func TestPOLOAuthRejectsInvalidRegistration(t *testing.T) {
	valid := polTestConfig("https://oauth.invalid")
	mutations := []func(*POLClientConfig){
		func(c *POLClientConfig) { c.ClientID = firefoxClientID },
		func(c *POLClientConfig) { c.ClientID = "" },
		func(c *POLClientConfig) { c.AuthorizationEndpoint = "http://oauth.invalid/authorize" },
		func(c *POLClientConfig) { c.AuthorizationEndpoint += "?extra=yes" },
		func(c *POLClientConfig) { c.TokenEndpoint = "https://user@oauth.invalid/token" },
		func(c *POLClientConfig) { c.TokenEndpoint += "#" },
		func(c *POLClientConfig) { c.TokenEndpoint = "https://oauth.invalid//token" },
		func(c *POLClientConfig) { c.RedirectURI = "http://oauth.invalid/callback" },
		func(c *POLClientConfig) { c.RedirectURI = "com.polvpn.app://oauth2redirect" },
		func(c *POLClientConfig) { c.RedirectURI += "?fixed=1" },
		func(c *POLClientConfig) { c.Scopes = nil },
		func(c *POLClientConfig) { c.Scopes = []string{"two scopes"} },
		func(c *POLClientConfig) { c.Scopes = []string{"duplicate", "duplicate"} },
	}
	for i, mutate := range mutations {
		config := valid
		mutate(&config)
		if _, err := NewPOLClient(config); !errors.Is(err, ErrPOLClientConfig) {
			t.Fatalf("Registration %d should be rejected, got %v", i, err)
		}
	}
	valid.RedirectURI = "https://pol.invalid/oauth2redirect"
	if _, err := NewPOLClient(valid); err != nil {
		t.Fatalf("Expected a valid registered HTTPS redirect, got %v", err)
	}
}

func TestPOLOAuthFailsClosedOnTokenResponses(t *testing.T) {
	const private = "private-response-diagnostic"
	for _, tc := range []struct {
		name, body string
		status     int
		kind       POLOAuthErrorKind
	}{
		{"redirect", private, http.StatusTemporaryRedirect, POLOAuthRedirect},
		{"invalid grant", `{"error":"invalid_grant","error_description":"` + private + `"}`, http.StatusBadRequest, POLOAuthInvalidGrant},
		{"partial error object", `{"error":"invalid_grant",` + private, http.StatusBadRequest, POLOAuthRejected},
		{"regional refusal", `{"error":"invalid_grant","error_description":"` + private + `"}`, http.StatusUnavailableForLegalReasons, POLOAuthRejected},
		{"oversized reply", strings.Repeat(" ", polMaxResponse+1) + private, http.StatusOK, POLOAuthInvalidReply},
		{"unrequested scope", `{"access_token":"fixture-access","expires_in":3600,"token_type":"bearer","scope":"other"}`, http.StatusOK, POLOAuthInvalidReply},
		{"missing bearer type", `{"access_token":"fixture-access","expires_in":3600}`, http.StatusOK, POLOAuthInvalidReply},
		{"invalid expiry", `{"access_token":"fixture-access","expires_in":0,"token_type":"bearer"}`, http.StatusOK, POLOAuthInvalidReply},
		{"unsafe token", `{"access_token":"a\nb","expires_in":3600,"token_type":"bearer"}`, http.StatusOK, POLOAuthInvalidReply},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var requests atomic.Int32
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if r.URL.Path == "/token" && tc.status == http.StatusTemporaryRedirect {
					w.Header().Set("Location", "/must-not-contact")
				}
				w.WriteHeader(tc.status)
				fmt.Fprint(w, tc.body)
			}))
			defer server.Close()
			client, err := newPOLClient(polTestConfig(server.URL), server.Client().Transport)
			if err != nil {
				t.Fatal(err)
			}
			_, err = client.Refresh(t.Context(), "fixture-refresh")
			var outcome *POLOAuthError
			if !errors.As(err, &outcome) || outcome.HTTPStatus != tc.status || outcome.Kind != tc.kind ||
				strings.Contains(err.Error(), private) {
				t.Fatalf("Expected sanitized %q with HTTP %d, got %v", tc.kind, tc.status, err)
			}
			if requests.Load() != 1 {
				t.Fatal("The token request must not follow redirects")
			}
			ctx, cancel := context.WithCancel(t.Context())
			cancel()
			if _, err := client.Refresh(ctx, "fixture-refresh"); !errors.Is(err, context.Canceled) {
				t.Fatalf("Expected request cancellation, got %v", err)
			}
		})
	}
}
