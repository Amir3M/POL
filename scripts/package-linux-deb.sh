#!/usr/bin/env bash
# Package an AMiR VPN Linux x64 release archive without rebuilding it.
set -euo pipefail

archive="$(realpath "$1")"
version="$2"
output="$(realpath -m "$3")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/package"
install -d "$root/DEBIAN" "$root/usr/lib" "$root/usr/bin"
tar --no-same-owner -xzf "$archive" -C "$root/usr/lib"
bundle="$root/usr/lib/amir-vpn"
test -x "$bundle/arman-vpn"
test -x "$bundle/core/arman-vpn-core"
test -x "$bundle/core/arman-vpn-tun"
test ! -e "$bundle/portable"

ln -s ../lib/amir-vpn/arman-vpn "$root/usr/bin/amir-vpn"
install -Dm644 "$bundle/data/app_icon.png" \
  "$root/usr/share/icons/hicolor/256x256/apps/amir-vpn.png"
install -Dm644 "$bundle/LICENSE" "$root/usr/share/doc/amir-vpn/copyright"
install -d "$root/usr/share/applications"
cat >"$root/usr/share/applications/amir-vpn.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AMiR VPN
Comment=VPN and network proxy client
Exec=amir-vpn
Icon=amir-vpn
Terminal=false
Categories=Network;Security;
StartupWMClass=com.arman.firefoxvpn
EOF

installed_size="$(du -sk "$root/usr" | cut -f1)"
cat >"$root/DEBIAN/control" <<EOF
Package: amir-vpn
Version: $version
Architecture: amd64
Maintainer: AMiR VPN <43105035+Amir3M@users.noreply.github.com>
Section: net
Priority: optional
Installed-Size: $installed_size
Depends: libc6 (>= 2.35), libstdc++6, libgtk-3-0t64 | libgtk-3-0, libepoxy0, libegl1, libgl1, libxkbcommon0, ca-certificates
Recommends: libayatana-appindicator3-1, pkexec | policykit-1
Homepage: https://github.com/Amir3M/POL
Description: AMiR VPN desktop client
 An independently branded build of the Arman VPN open-source client.
EOF

mkdir -p "$(dirname "$output")"
dpkg-deb --root-owner-group --build "$root" "$output"
(cd "$(dirname "$output")" && sha256sum "$(basename "$output")" > "$(basename "$output").sha256")
