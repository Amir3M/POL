package fxa

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path"
	"strings"
	"sync/atomic"
	"time"
)

const (
	polAuthorizationTTL = 10 * time.Minute
	polTokenTimeout     = 20 * time.Second
	polMaxResponse      = 64 * 1024
	polMaxCallback      = 16 * 1024
	polMaxToken         = 16 * 1024
)

var (
	ErrPOLClientConfig      = errors.New("invalid POL OAuth registration")
	ErrPOLCallback          = errors.New("invalid POL OAuth callback")
	ErrPOLAuthorizationUsed = errors.New("POL OAuth authorization already used")
	ErrPOLAuthorizationOld  = errors.New("POL OAuth authorization expired")
	ErrPOLRefreshToken      = errors.New("missing or invalid POL OAuth refresh token")
)

// POLClientConfig describes a provider-approved native public OAuth client.
// The provider must support an external browser, authorization code with
// S256 PKCE, form token requests and a refresh token for this registration.
// Nothing in this package provisions that approval or supplies live defaults.
type POLClientConfig struct {
	ClientID              string
	AuthorizationEndpoint string
	TokenEndpoint         string
	RedirectURI           string
	Scopes                []string
}

// POLClient implements OAuth for a registered POL identity independently of
// the inherited Firefox client. Callers should keep it scoped to one provider.
type POLClient struct {
	clientID, redirectURI string
	authorizationEndpoint url.URL
	tokenEndpoint         string
	scopes                map[string]struct{}
	scope                 string
	http                  *http.Client
}

// POLOAuthErrorKind is a stable, sanitized endpoint or callback outcome.
type POLOAuthErrorKind string

const (
	POLOAuthDenied        POLOAuthErrorKind = "authorization denied"
	POLOAuthUnavailable   POLOAuthErrorKind = "provider unavailable"
	POLOAuthRedirect      POLOAuthErrorKind = "unexpected token endpoint redirect"
	POLOAuthInvalidGrant  POLOAuthErrorKind = "grant rejected"
	POLOAuthInvalidClient POLOAuthErrorKind = "client rejected"
	POLOAuthInvalidScope  POLOAuthErrorKind = "scope rejected"
	POLOAuthRejected      POLOAuthErrorKind = "request rejected"
	POLOAuthInvalidReply  POLOAuthErrorKind = "invalid token response"
)

// POLOAuthError carries only a stable classification and optional HTTP status.
type POLOAuthError struct {
	Kind       POLOAuthErrorKind
	HTTPStatus int
}

func (e *POLOAuthError) Error() string {
	if e.HTTPStatus == 0 {
		return "POL OAuth: " + string(e.Kind)
	}
	return fmt.Sprintf("POL OAuth: %s (HTTP %d)", e.Kind, e.HTTPStatus)
}

// NewPOLClient creates a direct HTTPS client for the exact approved endpoints.
// It does not consult proxy settings or the upstream control plane.
func NewPOLClient(config POLClientConfig) (*POLClient, error) {
	dialer := &net.Dialer{Timeout: 8 * time.Second, KeepAlive: 30 * time.Second}
	return newPOLClient(config, &http.Transport{
		DialContext:            dialer.DialContext,
		TLSClientConfig:        &tls.Config{MinVersion: tls.VersionTLS12},
		ForceAttemptHTTP2:      true,
		TLSHandshakeTimeout:    8 * time.Second,
		IdleConnTimeout:        30 * time.Second,
		MaxResponseHeaderBytes: 32 * 1024,
	})
}

func newPOLClient(config POLClientConfig, transport http.RoundTripper) (*POLClient, error) {
	auth, authOK := parsePOLURL(config.AuthorizationEndpoint)
	token, tokenOK := parsePOLURL(config.TokenEndpoint)
	redirect, redirectOK := parsePOLURL(config.RedirectURI)
	if !authOK || auth.Scheme != "https" || auth.Hostname() == "" ||
		!tokenOK || token.Scheme != "https" || token.Hostname() == "" ||
		!redirectOK || !isPOLRedirect(redirect) ||
		!opaquePOLValue(config.ClientID, 256) || strings.EqualFold(config.ClientID, firefoxClientID) ||
		len(config.Scopes) == 0 || transport == nil {
		return nil, ErrPOLClientConfig
	}
	scopes := make(map[string]struct{}, len(config.Scopes))
	for _, item := range config.Scopes {
		if !opaquePOLValue(item, 512) || strings.ContainsAny(item, "\\\"") {
			return nil, ErrPOLClientConfig
		}
		if _, exists := scopes[item]; exists {
			return nil, ErrPOLClientConfig
		}
		scopes[item] = struct{}{}
	}
	scope := strings.Join(config.Scopes, " ")
	if len(scope) > 2048 {
		return nil, ErrPOLClientConfig
	}
	return &POLClient{
		clientID:              config.ClientID,
		redirectURI:           config.RedirectURI,
		authorizationEndpoint: *auth,
		tokenEndpoint:         config.TokenEndpoint,
		scopes:                scopes,
		scope:                 scope,
		http: &http.Client{
			Transport: transport,
			Timeout:   polTokenTimeout,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}, nil
}

func parsePOLURL(raw string) (*url.URL, bool) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Opaque != "" || u.User != nil ||
		strings.ContainsAny(raw, "?#") || u.RawPath != "" ||
		strings.HasPrefix(u.Path, "//") || !strings.HasPrefix(raw, u.Scheme+":") {
		return nil, false
	}
	if u.Path != "" && path.Clean(u.Path) != strings.TrimSuffix(u.Path, "/") && u.Path != "/" {
		return nil, false
	}
	return u, true
}

func isPOLRedirect(u *url.URL) bool {
	if u.Scheme == "https" {
		return u.Hostname() != ""
	}
	// RFC 8252 private-use schemes use a reverse-domain name and no authority.
	return strings.Contains(u.Scheme, ".") && u.OmitHost && u.Host == "" && strings.HasPrefix(u.Path, "/")
}

// POLAuthorization is a short-lived, single-use OAuth attempt. Keep it in
// native memory and give only URL() to the external browser.
type POLAuthorization struct {
	authorization string
	transaction   *polOAuthTransaction
}

type polOAuthTransaction struct {
	client    *POLClient
	state     string
	verifier  string
	expiresAt time.Time
	used      atomic.Bool
}

// URL returns the authorization URL for the external system browser.
func (a *POLAuthorization) URL() string { return a.authorization }

// BeginAuthorization prepares an S256 PKCE authorization-code request.
func (c *POLClient) BeginAuthorization() (*POLAuthorization, error) {
	state, err := randomPOLValue()
	if err != nil {
		return nil, err
	}
	verifier, err := randomPOLValue()
	if err != nil {
		return nil, err
	}
	challenge := sha256.Sum256([]byte(verifier))
	u := c.authorizationEndpoint
	u.RawQuery = url.Values{
		"client_id":             {c.clientID},
		"redirect_uri":          {c.redirectURI},
		"response_type":         {"code"},
		"scope":                 {c.scope},
		"state":                 {state},
		"code_challenge_method": {"S256"},
		"code_challenge":        {base64.RawURLEncoding.EncodeToString(challenge[:])},
	}.Encode()
	return &POLAuthorization{
		authorization: u.String(),
		transaction: &polOAuthTransaction{
			client: c, state: state, verifier: verifier,
			expiresAt: time.Now().Add(polAuthorizationTTL),
		},
	}, nil
}

func randomPOLValue() (string, error) {
	var bytes [32]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", errors.New("POL OAuth could not generate an authorization value")
	}
	return base64.RawURLEncoding.EncodeToString(bytes[:]), nil
}

// Exchange validates the registered redirect and state before consuming the
// attempt. A valid-state callback consumes it even if the provider denied
// access or the token request later fails.
func (c *POLClient) Exchange(ctx context.Context, attempt *POLAuthorization, callback string) (*TokenResponse, error) {
	if attempt == nil || attempt.transaction == nil || attempt.transaction.client != c || len(callback) > polMaxCallback {
		return nil, ErrPOLCallback
	}
	transaction := attempt.transaction
	base, query, hasQuery := strings.Cut(callback, "?")
	if !hasQuery || base != c.redirectURI || strings.Contains(query, "#") {
		return nil, ErrPOLCallback
	}
	params, err := url.ParseQuery(query)
	if err != nil || len(params["state"]) != 1 ||
		subtle.ConstantTimeCompare([]byte(params.Get("state")), []byte(transaction.state)) != 1 {
		return nil, ErrPOLCallback
	}
	if !time.Now().Before(transaction.expiresAt) {
		return nil, ErrPOLAuthorizationOld
	}
	if !transaction.used.CompareAndSwap(false, true) {
		return nil, ErrPOLAuthorizationUsed
	}
	verifier := transaction.verifier
	transaction.verifier = ""
	if len(params["error"]) == 1 && params.Get("error") == "access_denied" && len(params["code"]) == 0 {
		return nil, &POLOAuthError{Kind: POLOAuthDenied}
	}
	code := params.Get("code")
	if len(params["error"]) != 0 || len(params["code"]) != 1 || !opaquePOLValue(code, 4096) {
		return nil, ErrPOLCallback
	}
	return c.tokenRequest(ctx, url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"redirect_uri":  {c.redirectURI},
		"code_verifier": {verifier},
	}, "")
}

// Refresh renews a grant using the same POL client registration. If the
// provider omits a rotated refresh token, retain the current refresh token.
// The caller should retain the previous scope when the response omits it.
func (c *POLClient) Refresh(ctx context.Context, refreshToken string) (*TokenResponse, error) {
	if !opaquePOLValue(refreshToken, polMaxToken) {
		return nil, ErrPOLRefreshToken
	}
	return c.tokenRequest(ctx, url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {refreshToken},
	}, refreshToken)
}

func (c *POLClient) tokenRequest(ctx context.Context, form url.Values, previousRefresh string) (*TokenResponse, error) {
	form.Set("client_id", c.clientID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenEndpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, &POLOAuthError{Kind: POLOAuthUnavailable}
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, &POLOAuthError{Kind: POLOAuthUnavailable}
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 && resp.StatusCode < 400 {
		return nil, &POLOAuthError{Kind: POLOAuthRedirect, HTTPStatus: resp.StatusCode}
	}
	var wire struct {
		TokenResponse
		Error string `json:"error"`
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, polMaxResponse+1))
	valid := err == nil && len(data) <= polMaxResponse && json.Unmarshal(data, &wire) == nil
	if resp.StatusCode != http.StatusOK {
		code := ""
		if valid && (resp.StatusCode == http.StatusBadRequest ||
			resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden) {
			code = wire.Error
		}
		return nil, polTokenError(resp.StatusCode, code)
	}
	if !valid || wire.Error != "" || !opaquePOLValue(wire.AccessToken, polMaxToken) ||
		!strings.EqualFold(wire.TokenType, "bearer") || wire.ExpiresIn <= 0 ||
		time.Duration(wire.ExpiresIn) > time.Duration(1<<63-1)/time.Second ||
		!c.approvedScope(wire.Scope) {
		return nil, &POLOAuthError{Kind: POLOAuthInvalidReply, HTTPStatus: resp.StatusCode}
	}
	if wire.RefreshToken == "" {
		wire.RefreshToken = previousRefresh
	}
	if !opaquePOLValue(wire.RefreshToken, polMaxToken) {
		return nil, &POLOAuthError{Kind: POLOAuthInvalidReply, HTTPStatus: resp.StatusCode}
	}
	return &wire.TokenResponse, nil
}

func (c *POLClient) approvedScope(scope string) bool {
	if scope == "" {
		return true
	}
	for _, item := range strings.Split(scope, " ") {
		if _, ok := c.scopes[item]; !ok {
			return false
		}
	}
	return true
}

func polTokenError(status int, code string) *POLOAuthError {
	kind := POLOAuthRejected
	switch code {
	case "invalid_grant":
		kind = POLOAuthInvalidGrant
	case "invalid_client", "unauthorized_client":
		kind = POLOAuthInvalidClient
	case "invalid_scope":
		kind = POLOAuthInvalidScope
	case "temporarily_unavailable":
		kind = POLOAuthUnavailable
	}
	if status >= 500 {
		kind = POLOAuthUnavailable
	}
	return &POLOAuthError{Kind: kind, HTTPStatus: status}
}

func opaquePOLValue(value string, max int) bool {
	if len(value) == 0 || len(value) > max {
		return false
	}
	for _, ch := range value {
		if ch < 0x21 || ch > 0x7e {
			return false
		}
	}
	return true
}
