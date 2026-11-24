//go:build poltunneltest

package proxy

import "context"

// RenewTunnelFixtureAuth refreshes the fixture account without changing the
// established upstream proxy pass or tunnel connections.
func (c *Controller) RenewTunnelFixtureAuth(ctx context.Context) error {
	c.renewMu.Lock()
	defer c.renewMu.Unlock()
	c.mu.Lock()
	auth := c.auth
	c.mu.Unlock()

	refreshed, err := refreshRuntimeAuth(ctx, auth)
	if err != nil {
		return err
	}

	c.mu.Lock()
	c.auth = refreshed
	c.mu.Unlock()
	return nil
}
