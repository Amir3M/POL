#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

apk="$(realpath -- "${1:?Supply a verified POL APK}")"
out="$(dirname -- "$apk")"
commit="$(git -C "$POL_REPO_ROOT" rev-parse HEAD)"
git -C "$POL_REPO_ROOT" diff --quiet HEAD -- app core scripts ||
    pol_error "Package source from the clean build commit."
(cd -- "$out" && sha256sum --check "$(basename -- "$apk").sha256")

package_tmp="$(mktemp -d "$out/.android-source.XXXXXX")"
trap 'rm -rf -- "$package_tmp"' EXIT
notices="$package_tmp/notices"
mkdir -p "$notices/go"
(
    cd -- "$POL_REPO_ROOT"
    cp --parents LICENSE app/assets/flags/LICENSE core/internal/service/web/flags/LICENSE \
        app/assets/fonts/OFL.txt app/assets/fonts/Inter/OFL.txt "$notices"
    find app/android/hev-socks5-tunnel -type f -name LICENSE -exec cp --parents -t "$notices" {} +
    git archive --format=tar.gz --prefix=pol-vpn-source/ --output="$package_tmp/pol-vpn-source.tar.gz" "$commit"
)
unzip -p "$apk" assets/flutter_assets/NOTICES.Z | gzip -dc > "$notices/Flutter-NOTICES.txt"

# The binding generator contributes its Java and Go runtime to the AAR.
cp "$(go env GOROOT)/LICENSE" "$notices/go/LICENSE"
modules="$package_tmp/go-modules"
(
    cd -- "$POL_REPO_ROOT/core"
    for arch in arm64 arm amd64; do
        GOOS=android GOARCH="$arch" CGO_ENABLED=1 go list -deps \
            -f '{{with .Module}}{{if not .Main}}{{.Path}}{{"\t"}}{{.Version}}{{"\t"}}{{.Dir}}{{end}}{{end}}' ./mobile
    done
    go list -m -f '{{.Path}}{{"\t"}}{{.Version}}{{"\t"}}{{.Dir}}' golang.org/x/mobile
) | sed '/^$/d' | sort -u > "$modules"

while IFS=$'\t' read -r module version directory; do
    destination="$notices/go/$module@$version"
    mkdir -p "$destination"
    find "$directory" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'notice*' -o -iname 'copying*' \) \
        -exec cp -t "$destination" {} +
    [[ -n "$(ls -A -- "$destination")" ]] || pol_error "No license files found for $module@$version."
done < "$modules"

tar -czf "$package_tmp/pol-vpn-notices.tar.gz" -C "$package_tmp" notices
mv -- "$package_tmp/pol-vpn-source.tar.gz" "$package_tmp/pol-vpn-notices.tar.gz" "$out/"
