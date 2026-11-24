// Package polonline owns the session and direct Guardian boundary for a
// provider-approved POL client. Android does not start it without a provider
// contract and a registered browser callback.
package polonline

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
	"github.com/armanlife/arman-vpn-client/core/internal/guardian"
)

// Config comes from the reviewed POL provider registration. It has no
// defaults and contains no client secret, account data, or device credentials.
type Config struct {
	OAuth          fxa.POLClientConfig
	GuardianOrigin string
}

// Store holds one opaque session bound to the provider registration. Android
// must implement it with the real-session Keystore store and no backup access.
// Load returns an empty string if no session exists. Save replaces atomically.
type Store interface {
	Load() (string, error)
	Save(string) error
	Clear() error
}

type oauthClient interface {
	BeginAuthorization() (*fxa.POLAuthorization, error)
	Exchange(context.Context, *fxa.POLAuthorization, string) (*fxa.TokenResponse, error)
	Refresh(context.Context, string) (*fxa.TokenResponse, error)
}

type guardianClient interface {
	FetchProxyPass(context.Context, string) (*guardian.ProxyPassInfo, error)
}

// Session serializes OAuth, credential storage and Guardian operations.
// Snapshot is available separately so observation cannot block on a request.
type Session struct {
	oauth    oauthClient
	guardian guardianClient
	store    Store
	binding  string
	now      func() time.Time

	mu      sync.Mutex
	pending *fxa.POLAuthorization
	tokens  *fxa.SavedTokens
	status  atomic.Value
}

type savedSession struct {
	Binding string          `json:"binding"`
	Tokens  fxa.SavedTokens `json:"tokens"`
}

func NewSession(config Config, store Store) (*Session, error) {
	if store == nil {
		return nil, errors.New("POL session storage is required")
	}
	oauth, err := fxa.NewPOLClient(config.OAuth)
	if err != nil {
		return nil, err
	}
	direct, err := guardian.NewDirectClient(config.GuardianOrigin)
	if err != nil {
		return nil, err
	}
	serialized, err := json.Marshal(config)
	if err != nil {
		return nil, errors.New("invalid POL provider configuration")
	}
	binding := sha256.Sum256(serialized)
	s := &Session{
		oauth: oauth, guardian: direct, store: store,
		binding: hex.EncodeToString(binding[:]), now: time.Now,
	}
	s.record("sign_in", 0, "session_required", nil)
	return s, nil
}

func (s *Session) Restore() (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.pending, s.tokens = nil, nil
	blob, err := s.store.Load()
	if err != nil {
		return false, s.fail("sign_in", 0, "session_storage", nil)
	}
	if blob == "" {
		s.record("sign_in", 0, "session_required", nil)
		return false, nil
	}
	var stored savedSession
	if len(blob) > 64<<10 || json.Unmarshal([]byte(blob), &stored) != nil ||
		stored.Binding != s.binding || !validTokens(stored.Tokens) {
		return false, s.fail("sign_in", 0, "session_storage", nil)
	}
	s.tokens = &stored.Tokens
	s.record("sign_in", 0, "", nil)
	return true, nil
}

// BeginSignIn returns the authorization URL for an external system browser.
func (s *Session) BeginSignIn() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	authorization, err := s.oauth.BeginAuthorization()
	if err != nil {
		s.pending = nil
		return "", s.fail("sign_in", 0, "request_failed", nil)
	}
	s.pending = authorization
	s.record("sign_in", 0, "", nil)
	return authorization.URL(), nil
}

func (s *Session) CompleteSignIn(ctx context.Context, callback string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	authorization := s.pending
	s.pending = nil
	if authorization == nil {
		return s.fail("sign_in", 0, "session_required", nil)
	}
	token, err := s.oauth.Exchange(ctx, authorization, callback)
	if err != nil {
		return s.oauthFailure(err)
	}
	return s.saveToken(token)
}

// ProxyPass refreshes the POL OAuth session when needed, then requests a pass
// directly. The returned pass is for the existing H2 proxy, never diagnostics.
func (s *Session) ProxyPass(ctx context.Context) (*guardian.ProxyPassInfo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.tokens == nil {
		return nil, s.fail("sign_in", 0, "session_required", nil)
	}
	lifetime := time.Duration(s.tokens.ExpiresIn) * time.Second
	refreshAt := s.tokens.ObtainedAt.Add(lifetime - min(2*time.Minute, lifetime/10))
	if !s.now().Before(refreshAt) {
		s.record("sign_in", 0, "", nil)
		token, err := s.oauth.Refresh(ctx, s.tokens.RefreshToken)
		if err != nil {
			var rejected *fxa.POLOAuthError
			if errors.As(err, &rejected) && rejected.Kind == fxa.POLOAuthInvalidGrant {
				s.tokens = nil
				if s.store.Clear() != nil {
					return nil, s.fail("sign_in", rejected.HTTPStatus, "session_storage", nil)
				}
			}
			return nil, s.oauthFailure(err)
		}
		if err := s.saveToken(token); err != nil {
			return nil, err
		}
	}
	s.record("guardian", 0, "", nil)
	pass, err := s.guardian.FetchProxyPass(ctx, s.tokens.AccessToken)
	if err != nil {
		return nil, s.guardianFailure(err)
	}
	if pass == nil {
		return nil, s.fail("proxy_pass", 200, "invalid_response", nil)
	}
	s.record("proxy_pass", 200, "", pass.Usage)
	return pass, nil
}

func (s *Session) Logout() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.pending, s.tokens = nil, nil
	if err := s.store.Clear(); err != nil {
		return s.fail("sign_in", 0, "session_storage", nil)
	}
	s.record("sign_in", 0, "session_required", nil)
	return nil
}

func (s *Session) saveToken(token *fxa.TokenResponse) error {
	if token == nil {
		return s.fail("sign_in", 0, "invalid_response", nil)
	}
	saved := savedSession{Binding: s.binding, Tokens: fxa.SavedTokens{
		AccessToken: token.AccessToken, RefreshToken: token.RefreshToken, Scope: token.Scope,
		ObtainedAt: s.now(), ExpiresIn: token.ExpiresIn,
	}}
	if !validTokens(saved.Tokens) {
		return s.fail("sign_in", 0, "invalid_response", nil)
	}
	blob, err := json.Marshal(saved)
	if err != nil || len(blob) > 64<<10 || s.store.Save(string(blob)) != nil {
		// A refresh may already have rotated the previous credential.
		s.tokens = nil
		return s.fail("sign_in", 0, "session_storage", nil)
	}
	s.tokens = &saved.Tokens
	s.record("sign_in", 200, "", nil)
	return nil
}

func validTokens(token fxa.SavedTokens) bool {
	return token.AccessToken != "" && token.RefreshToken != "" && !token.ObtainedAt.IsZero() &&
		token.ExpiresIn > 0 && int64(token.ExpiresIn) <= int64((1<<63-1)/time.Second)
}
