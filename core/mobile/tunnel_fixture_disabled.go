//go:build !poltunneltest

package mobile

import "errors"

var errTunnelFixtureDisabled = errors.New("the local tunnel fixture is disabled in this build")

func StartTunnelTest(dataRoot, sessionID string) error { return errTunnelFixtureDisabled }

func StopTunnelTest() {}

func RenewTunnelTest() error { return errTunnelFixtureDisabled }

func TunnelTestStatus() string { return `{"state":"disconnected"}` }
