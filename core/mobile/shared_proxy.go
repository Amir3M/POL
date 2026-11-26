package mobile

import (
	"encoding/json"
	"errors"
)

// SetSharedProxy enables the authenticated proxy on the IPv4 address and
// prefix selected by Android. An empty address stops sharing.
func SetSharedProxy(bindAddress string, prefixLength int32) (string, error) {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		if bindAddress == "" {
			return "{}", nil
		}
		return "", errors.New("the Android core is not running")
	}
	info, err := d.SetSharedProxy(bindAddress, int(prefixLength))
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(info)
	return string(data), err
}

// RotateSharedProxyCredentials disconnects clients with the previous login
// and returns fresh credentials for the same address and port.
func RotateSharedProxyCredentials() (string, error) {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		return "", errors.New("the Android core is not running")
	}
	info, err := d.RotateSharedProxyCredentials()
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(info)
	return string(data), err
}
