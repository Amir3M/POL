//go:build !poltunneltest

package mobile

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestTunnelFixtureDisabled(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "never-created")
	if err := StartTunnelTest(dir, "synthetic-local-session-id"); !errors.Is(err, errTunnelFixtureDisabled) {
		t.Fatalf("unexpected fixture startup result: %v", err)
	}
	if err := RenewTunnelTest(); !errors.Is(err, errTunnelFixtureDisabled) {
		t.Fatalf("unexpected fixture renewal result: %v", err)
	}
	StopTunnelTest()
	if Running() || TunnelTestStatus() != `{"state":"disconnected"}` {
		t.Fatal("the fixture activated in an ordinary build")
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("ordinary build created fixture state")
	}
}
