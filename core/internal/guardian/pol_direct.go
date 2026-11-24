package guardian

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	directTokenPath = "/api/v1/fpn/token"
	maxDirectPass   = 64 * 1024
)

// DirectClient sends canonical Guardian requests to one approved HTTPS origin.
// Its transport is independent of the upstream relay and recovery policies.
// The caller supplies an access token issued to the authorized POL client.
type DirectClient struct {
	tokenURL string
	client   *http.Client
}

// NewDirectClient requires an explicit HTTPS origin and uses system TLS roots.
func NewDirectClient(origin string) (*DirectClient, error) {
	return newDirectClient(origin, nil)
}

func newDirectClient(origin string, roots *x509.CertPool) (*DirectClient, error) {
	u, err := url.Parse(origin)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil ||
		(u.Path != "" && u.Path != "/") || u.RawPath != "" || u.RawQuery != "" || u.ForceQuery ||
		strings.Contains(origin, "#") || strings.HasSuffix(u.Host, ":") {
		return nil, errors.New("Guardian requires an explicit HTTPS origin")
	}
	if port := u.Port(); port != "" {
		n, err := strconv.ParseUint(port, 10, 16)
		if err != nil || n == 0 {
			return nil, errors.New("Guardian HTTPS origin has an invalid port")
		}
	}
	u.Path = directTokenPath

	return &DirectClient{
		tokenURL: u.String(),
		client: &http.Client{
			Timeout: TokenRequestTimeout,
			Transport: &http.Transport{
				Proxy:                 nil,
				DialContext:           (&net.Dialer{Timeout: 10 * time.Second}).DialContext,
				TLSClientConfig:       &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: roots},
				TLSHandshakeTimeout:   10 * time.Second,
				ForceAttemptHTTP2:     true,
				ResponseHeaderTimeout: 15 * time.Second,
				IdleConnTimeout:       time.Minute,
				MaxIdleConnsPerHost:   2,
			},
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		},
	}, nil
}

// DirectErrorKind identifies the stage where a direct request failed.
type DirectErrorKind string

const (
	DirectInvalidAccessToken DirectErrorKind = "invalid_access_token"
	DirectNoHTTPResponse     DirectErrorKind = "no_http_response"
	DirectHTTPRejected       DirectErrorKind = "http_rejected"
	DirectInvalidProxyPass   DirectErrorKind = "invalid_proxy_pass"
	DirectInvalidQuota       DirectErrorKind = "invalid_quota"
)

// DirectError reports a sanitized stage, HTTP status and service quota.
// StatusCode is zero when no HTTP response arrived.
type DirectError struct {
	Kind       DirectErrorKind
	StatusCode int
	RetryAfter time.Duration
	Usage      *ProxyUsage
	cause      error
}

func (e *DirectError) Error() string {
	if e.StatusCode == 0 {
		return "direct Guardian: " + string(e.Kind)
	}
	return fmt.Sprintf("direct Guardian: %s (HTTP %d)", e.Kind, e.StatusCode)
}

func (e *DirectError) Unwrap() error { return e.cause }

func (e *DirectError) Is(target error) bool {
	if e.Kind != DirectHTTPRejected {
		return false
	}
	switch e.StatusCode {
	case http.StatusUnauthorized:
		return target == ErrTokenInvalid
	case http.StatusForbidden:
		return target == ErrNotEntitled
	case http.StatusTooManyRequests:
		return target == ErrQuotaExceeded
	case http.StatusUnavailableForLegalReasons:
		return target == ErrRegionUnavailable
	default:
		return e.StatusCode >= 500 && e.StatusCode <= 599 && target == ErrServer
	}
}

// FetchProxyPass obtains one pass using the authorized Guardian control plane.
func (c *DirectClient) FetchProxyPass(ctx context.Context, accessToken string) (*ProxyPassInfo, error) {
	resp, err := c.request(ctx, http.MethodGet, accessToken)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	receivedAt := time.Now()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxDirectPass+1))
	if err != nil || len(body) > maxDirectPass {
		return nil, &DirectError{Kind: DirectInvalidProxyPass, StatusCode: resp.StatusCode, cause: ctx.Err()}
	}
	pass, err := decodeProxyPass(body, resp.Header, receivedAt)
	if err != nil || !validDirectBearer(pass.RawToken) || strings.HasPrefix(pass.RawToken, ".") ||
		strings.HasSuffix(pass.RawToken, ".") || !time.Unix(pass.Claims.Exp, 0).After(receivedAt) ||
		!pass.ExpiresAt().After(receivedAt) {
		return nil, &DirectError{Kind: DirectInvalidProxyPass, StatusCode: resp.StatusCode}
	}
	return pass, nil
}

// FetchProxyUsage reads quota without issuing a pass.
func (c *DirectClient) FetchProxyUsage(ctx context.Context, accessToken string) (*ProxyUsage, error) {
	resp, err := c.request(ctx, http.MethodHead, accessToken)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	usage, err := parseProxyUsage(resp.Header)
	if err != nil {
		return nil, &DirectError{Kind: DirectInvalidQuota, StatusCode: resp.StatusCode}
	}
	return usage, nil
}

func validDirectBearer(token string) bool {
	return token != "" && strings.IndexFunc(token, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' ||
			strings.ContainsRune("-._~+/=", r))
	}) == -1
}

func (c *DirectClient) request(ctx context.Context, method, accessToken string) (*http.Response, error) {
	if !validDirectBearer(accessToken) {
		return nil, &DirectError{Kind: DirectInvalidAccessToken}
	}
	req, err := http.NewRequestWithContext(ctx, method, c.tokenURL, nil)
	if err != nil {
		return nil, &DirectError{Kind: DirectNoHTTPResponse}
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("User-Agent", "POL-VPN")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Cache-Control", "no-cache")

	resp, err := c.client.Do(req)
	if err != nil {
		cause := ctx.Err()
		if cause == nil && errors.Is(err, context.DeadlineExceeded) {
			cause = context.DeadlineExceeded
		}
		return nil, &DirectError{Kind: DirectNoHTTPResponse, cause: cause}
	}
	if resp.StatusCode == http.StatusOK {
		return resp, nil
	}
	defer resp.Body.Close()
	failure := &DirectError{Kind: DirectHTTPRejected, StatusCode: resp.StatusCode}
	failure.Usage, _ = parseProxyUsage(resp.Header)
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		failure.RetryAfter = parseRetryAfter(resp.Header.Get("Retry-After"), time.Now())
	}
	return nil, failure
}
