package polonline

import (
	"context"
	"errors"

	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
	"github.com/armanlife/arman-vpn-client/core/internal/guardian"
)

// Snapshot contains only fields that may be displayed or exported.
type Snapshot struct {
	Enabled    bool   `json:"enabled"`
	Stage      string `json:"stage"`
	HTTPStatus int    `json:"httpStatus,omitempty"`
	Reason     string `json:"reason,omitempty"`
	Quota      *Quota `json:"quota,omitempty"`
}

type Quota struct {
	Unlimited bool   `json:"unlimited"`
	Limit     *int64 `json:"limit,omitempty"`
	Remaining *int64 `json:"remaining,omitempty"`
}

func (s *Session) Snapshot() Snapshot {
	status := s.status.Load().(Snapshot)
	if status.Quota != nil {
		quota := *status.Quota
		if quota.Limit != nil {
			limit, remaining := *quota.Limit, *quota.Remaining
			quota.Limit, quota.Remaining = &limit, &remaining
		}
		status.Quota = &quota
	}
	return status
}

func (s *Session) record(stage string, status int, reason string, usage *guardian.ProxyUsage) {
	if status < 100 || status > 599 {
		status = 0
	}
	snapshot := Snapshot{Enabled: true, Stage: stage, HTTPStatus: status, Reason: reason}
	if usage != nil {
		if usage.Unlimited {
			snapshot.Quota = &Quota{Unlimited: true}
		} else if usage.Limit >= 0 && usage.Remaining >= 0 && usage.Remaining <= usage.Limit {
			limit, remaining := usage.Limit, usage.Remaining
			snapshot.Quota = &Quota{Limit: &limit, Remaining: &remaining}
		}
	}
	s.status.Store(snapshot)
}

func (s *Session) fail(stage string, status int, reason string, usage *guardian.ProxyUsage) error {
	s.record(stage, status, reason, usage)
	return errors.New("POL " + stage + ": " + reason)
}

func (s *Session) oauthFailure(err error) error {
	reason := "request_failed"
	status := 0
	var oauthErr *fxa.POLOAuthError
	switch {
	case errors.As(err, &oauthErr):
		status = oauthErr.HTTPStatus
		switch oauthErr.Kind {
		case fxa.POLOAuthInvalidGrant, fxa.POLOAuthInvalidClient:
			reason = "unauthorized"
		case fxa.POLOAuthInvalidReply:
			reason = "invalid_response"
		case fxa.POLOAuthDenied, fxa.POLOAuthRejected, fxa.POLOAuthInvalidScope:
			reason = "rejected"
		case fxa.POLOAuthRedirect:
			reason = "redirect_refused"
		}
	case errors.Is(err, context.Canceled):
		reason = "cancelled"
	case errors.Is(err, fxa.ErrPOLCallback), errors.Is(err, fxa.ErrPOLAuthorizationUsed),
		errors.Is(err, fxa.ErrPOLAuthorizationOld):
		reason = "rejected"
	}
	return s.fail("sign_in", status, reason, nil)
}

func (s *Session) guardianFailure(err error) error {
	stage, reason := "guardian", "request_failed"
	status := 0
	var usage *guardian.ProxyUsage
	var directErr *guardian.DirectError
	if errors.As(err, &directErr) {
		status, usage = directErr.StatusCode, directErr.Usage
		switch {
		case errors.Is(err, context.Canceled):
			reason = "cancelled"
		case directErr.Kind == guardian.DirectInvalidAccessToken:
			reason = "unauthorized"
		case status == 200:
			stage, reason = "proxy_pass", "invalid_response"
		case status >= 300 && status <= 399:
			reason = "redirect_refused"
		case errors.Is(err, guardian.ErrNotEntitled):
			reason = "not_entitled"
		case errors.Is(err, guardian.ErrTokenInvalid):
			reason = "unauthorized"
		case errors.Is(err, guardian.ErrQuotaExceeded):
			reason = "quota_exhausted"
		case errors.Is(err, guardian.ErrRegionUnavailable):
			reason = "region_unavailable"
		case status >= 400:
			reason = "rejected"
		}
	} else if errors.Is(err, context.Canceled) {
		reason = "cancelled"
	}
	return s.fail(stage, status, reason, usage)
}
