#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

mode="${1:-debug}"
application_id="$(sed -n 's/^[[:space:]]*applicationId = "\([^"]*\)".*/\1/p' "$POL_REPO_ROOT/app/android/app/build.gradle.kts")"
case "$mode" in
    baseline)
        [[ "$application_id" == com.arman.firefoxvpn ]] ||
            pol_error "Set POL_REPO_ROOT to the untouched Arman VPN checkout for a baseline build."
        [[ ! -e "$POL_REPO_ROOT/app/android/key.properties" ]] ||
            pol_error "Build the baseline in a clean checkout without release signing properties."
        build_mode=release
        artifact=arman-vpn-baseline.apk
        expected_package=com.arman.firefoxvpn
        ;;
    debug)
        build_mode=debug
        artifact=pol-vpn-debug.apk
        expected_package=com.polvpn.app.debug
        ;;
    release)
        build_mode=release
        artifact=pol-vpn-release.apk
        expected_package=com.polvpn.app
        [[ -s "$POL_REPO_ROOT/app/android/key.properties" ]] ||
            pol_error "A production build requires app/android/key.properties."
        ;;
    *)
        pol_error "Usage: $0 [debug|release|baseline]"
        ;;
esac
if [[ "$mode" != baseline && "$application_id" != com.polvpn.app ]]; then
    pol_error "POL Android identity is pending. Use baseline mode in the pinned upstream worktree."
fi

pol_require_language_tools
pol_require_sdk
pol_check_mobile_tools || pol_error "Run scripts/setup-android.sh to install pinned gomobile and gobind."

version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$POL_REPO_ROOT/app/pubspec.yaml")"
module="$(awk '$1 == "module" { print $2; exit }' "$POL_REPO_ROOT/core/go.mod")"
[[ -n "$version" && -n "$module" ]] || pol_error "Could not read app version or Go module."

mkdir -p "$POL_REPO_ROOT/app/android/app/libs"
(
    cd -- "$POL_REPO_ROOT/core"
    gomobile bind -target=android -androidapi "$POL_ANDROID_MIN_API" -trimpath \
        -ldflags "-s -w -X $module/internal/version.Current=$version" \
        -o ../app/android/app/libs/core.aar ./mobile
)
(
    cd -- "$POL_REPO_ROOT/app"
    pol_pub_get
    flutter build apk "--$build_mode" --no-pub --dart-define="APP_VERSION=$version"
)

apk="$POL_REPO_ROOT/app/build/app/outputs/flutter-apk/app-$build_mode.apk"
build_tools="$ANDROID_HOME/build-tools/$POL_BUILD_TOOLS_VERSION"
"$build_tools/apksigner" verify --verbose "$apk"
package_id="$("$build_tools/aapt" dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
[[ "$package_id" == "$expected_package" ]] ||
    pol_error "APK package is '$package_id'; expected '$expected_package'."
out="${POL_ANDROID_ARTIFACT_DIR:-$POL_REPO_ROOT/out}"
mkdir -p "$out"
artifact_tmp="$(mktemp -d "$out/.android-artifacts.XXXXXX")"
trap 'rm -rf -- "$artifact_tmp"' EXIT
cp -- "$apk" "$artifact_tmp/$artifact"
(cd -- "$artifact_tmp" && sha256sum "$artifact" > "$artifact.sha256")
mv -- "$artifact_tmp/$artifact" "$artifact_tmp/$artifact.sha256" "$out/"
printf 'Built %s\n' "$out/$artifact"
