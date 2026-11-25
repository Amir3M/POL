package update

import (
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

// Source identifies an archive and its signed checksum list.
type Source struct {
	File         string `json:"file"`
	URL          string `json:"url"`
	ChecksumsURL string `json:"checksums_url"`
	SignatureURL string `json:"signature_url"`
}

const packageFile = "package.json"
const versionPrefix = "# Arman VPN version: "

func (m *Manager) defaultSource(v string) Source {
	base := m.baseURL + "v" + v + "/"
	name := AssetName(v)
	if m.baseURL == releasesURL && thePackage.releaseName != "" {
		name = thePackage.releaseName
	}
	return Source{name, base + name, base + SumsFile, base + SigFile}
}

func (s Source) validate() error {
	if err := validPackageName(s.File); err != nil {
		return err
	}
	for _, raw := range []string{s.URL, s.ChecksumsURL, s.SignatureURL} {
		u, err := url.Parse(raw)
		if err != nil || u.Hostname() == "" || u.User != nil || u.Fragment != "" {
			return fmt.Errorf("invalid update URL")
		}
		if u.Scheme != "https" && !(u.Scheme == "http" && isLoopback(u.Hostname())) {
			return fmt.Errorf("update URLs must use HTTPS")
		}
	}
	return nil
}

func isLoopback(host string) bool {
	ip := net.ParseIP(host)
	return host == "localhost" || (ip != nil && ip.IsLoopback())
}

// validateSource limits production downloads to the versioned assets in the
// AMiR VPN repository. Local update tests can supply paths on their own origin.
func (m *Manager) validateSource(v string, source Source) error {
	if err := source.validate(); err != nil {
		return err
	}
	if m.baseURL == releasesURL {
		if source != m.defaultSource(v) {
			return fmt.Errorf("updates must use assets from Amir3M/POL for version %s", v)
		}
		return nil
	}
	server, _ := url.Parse(m.baseURL)
	for _, raw := range []string{source.URL, source.ChecksumsURL, source.SignatureURL} {
		u, _ := url.Parse(raw)
		if u.Scheme != server.Scheme || u.Host != server.Host {
			return fmt.Errorf("test update URLs must use the configured local server")
		}
	}
	return nil
}

func validPackageName(name string) error {
	// Names are portable across the supported systems, including Windows.
	if name == "" || strings.ContainsAny(name, "/\\:\x00\r\n") || strings.Contains(name, "..") || strings.TrimSpace(name) != name {
		return fmt.Errorf("invalid update file name")
	}
	ending := ".tar.gz"
	if strings.HasSuffix(AssetName("1.0.0"), ".zip") {
		ending = ".zip"
	}
	if !strings.HasSuffix(name, ending) {
		return fmt.Errorf("the update package must be a %s archive", ending)
	}
	return nil
}

// checkedPackageHash binds a fixed filename to the requested version.
// New releases sign a version comment together with their checksums;
// earlier releases bind it through the signed versioned filename.
func checkedPackageHash(sums, sig []byte, name, v string) (string, error) {
	want, err := checkedHash(sums, sig, name)
	if err != nil {
		return "", err
	}
	var signedVersion string
	for _, line := range strings.Split(string(sums), "\n") {
		if value, ok := strings.CutPrefix(strings.TrimSpace(line), versionPrefix); ok {
			if signedVersion != "" {
				return "", bad("the release's checksum list repeats its version")
			}
			signedVersion = value
		}
	}
	if signedVersion != "" {
		if signedVersion != v {
			return "", bad("the signed release version does not match %s", v)
		}
	} else if ParseSums(sums)[AssetName(v)] != want {
		return "", bad("the signed checksum list does not bind the package to version %s", v)
	}
	return want, nil
}

func (m *Manager) cachedPackageName(v string) (string, error) {
	data, err := os.ReadFile(filepath.Join(m.versionDir(v), packageFile))
	if os.IsNotExist(err) {
		return AssetName(v), nil
	}
	if err != nil {
		return "", err
	}
	var saved struct {
		File string `json:"file"`
	}
	if err := json.Unmarshal(data, &saved); err != nil {
		return "", err
	}
	if err := validPackageName(saved.File); err != nil {
		return "", err
	}
	return saved.File, nil
}
