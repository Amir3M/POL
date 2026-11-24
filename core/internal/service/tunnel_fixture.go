//go:build poltunneltest

package service

import (
	"context"
	"errors"
)

// TunnelFixtureAuthority is the only test-network destination the Android
// fixture can carry. Its upstream maps it to a private loopback origin.
const TunnelFixtureAuthority = "192.0.2.1:8080"

// RestrictToTunnelFixture disables external probes and limits the private
// TUN listener. Call it before Run with the fixture's disposable config.
func (d *Daemon) RestrictToTunnelFixture() {
	d.tunnelFixtureAuthority = TunnelFixtureAuthority
}

// RenewTunnelFixtureSession refreshes the connected fixture account in place.
func (d *Daemon) RenewTunnelFixtureSession(ctx context.Context) error {
	if d.tunnelFixtureAuthority != TunnelFixtureAuthority {
		return errors.New("the daemon is outside the tunnel fixture")
	}
	if engine := d.currentEngine(); engine != nil {
		if controller := engine.currentController(); controller != nil {
			return controller.RenewTunnelFixtureAuth(ctx)
		}
	}
	return errors.New("the test tunnel must be connected before renewal")
}
