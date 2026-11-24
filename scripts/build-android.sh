#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

mode="${1:-debug}"
export POL_TUNNEL_TEST=0
mobile_options=()
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
    debug|tunnel-test)
        build_mode=debug
        artifact=pol-vpn-debug.apk
        expected_package=com.polvpn.app.debug
        if [[ "$mode" == tunnel-test ]]; then
            export POL_TUNNEL_TEST=1
            mobile_options+=(-tags poltunneltest)
        fi
        ;;
    release)
        build_mode=release
        artifact=pol-vpn-release.apk
        expected_package=com.polvpn.app
        [[ -s "$POL_REPO_ROOT/app/android/key.properties" ]] ||
            pol_error "A production build requires app/android/key.properties."
        ;;
    *)
        pol_error "Usage: $0 [debug|tunnel-test|release|baseline]"
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
dart_defines=("--dart-define=APP_VERSION=$version")
if [[ "$mode" == tunnel-test ]]; then
    dart_defines+=(--dart-define=POL_TUNNEL_TEST=true)
fi
if [[ "$mode" != baseline ]]; then
    build_id="$(git -C "$POL_REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'local')"
    if [[ "$build_id" != local ]] && ! git -C "$POL_REPO_ROOT" diff --quiet HEAD -- app core scripts; then
        build_id+="-dirty"
    fi
    dart_defines+=("--dart-define=POL_BUILD_ID=$build_id")
fi

mkdir -p "$POL_REPO_ROOT/app/android/app/libs"
(
    cd -- "$POL_REPO_ROOT/core"
    gomobile bind -target=android -androidapi "$POL_ANDROID_MIN_API" -trimpath "${mobile_options[@]}" \
        -ldflags "-s -w -X $module/internal/version.Current=$version" \
        -o ../app/android/app/libs/core.aar ./mobile
)
(
    cd -- "$POL_REPO_ROOT/app"
    pol_pub_get
    flutter build apk "--$build_mode" --no-pub "${dart_defines[@]}"
)

apk="$POL_REPO_ROOT/app/build/app/outputs/flutter-apk/app-$build_mode.apk"
build_tools="$ANDROID_HOME/build-tools/$POL_BUILD_TOOLS_VERSION"
"$build_tools/apksigner" verify --verbose "$apk"
badging="$("$build_tools/aapt" dump badging "$apk")"
package_id="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<< "$badging")"
[[ "$package_id" == "$expected_package" ]] ||
    pol_error "APK package is '$package_id'; expected '$expected_package'."

if [[ "$mode" == tunnel-test ]]; then
    permissions="$("$build_tools/aapt" dump permissions "$apk")"
    unexpected_permissions="$(awk -F "'" -v internal="$expected_package.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" '
        /^uses-permission/ && $2 != internal &&
        $2 !~ /^android\.permission\.(INTERNET|ACCESS_NETWORK_STATE|FOREGROUND_SERVICE|FOREGROUND_SERVICE_SPECIAL_USE|POST_NOTIFICATIONS)$/ { print }
    ' <<< "$permissions")"
    [[ -z "$unexpected_permissions" ]] ||
        pol_error "The tunnel-test APK requests unexpected permissions: $unexpected_permissions"
    launcher="$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" <<< "$badging")"
    [[ "$launcher" == com.arman.firefoxvpn.MainActivity ]] ||
        pol_error "The tunnel-test APK must launch MainActivity."
    manifest="$("$build_tools/aapt" dump xmltree "$apk" AndroidManifest.xml)"
    for required in com.arman.firefoxvpn.CoreService android.net.VpnService android.permission.BIND_VPN_SERVICE; do
        grep -Fq "\"$required\"" <<< "$manifest" ||
            pol_error "The tunnel-test manifest is missing $required."
    done
    if grep -Eq '\.PreviewActivity|\.QuickTile|\.ConnectWidget' <<< "$manifest"; then
        pol_error "The tunnel-test APK has an extra Android entry point."
    fi
    grep -Eq 'android:allowBackup.*=\(type 0x12\)0x0$' <<< "$manifest" ||
        pol_error "The tunnel-test APK must disable application backup."
elif [[ "$mode" != baseline ]]; then
    permissions="$("$build_tools/aapt" dump permissions "$apk")"
    unexpected_permissions="$(awk -F "'" -v internal="$expected_package.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" \
        '/^uses-permission/ && $2 != internal { print }' <<< "$permissions")"
    [[ -z "$unexpected_permissions" ]] ||
        pol_error "The offline APK requests unexpected permissions: $unexpected_permissions"

    manifest="$("$build_tools/aapt" dump xmltree "$apk" AndroidManifest.xml)"
    launcher="$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" <<< "$badging")"
    [[ "$launcher" == com.polvpn.app.PreviewActivity ]] ||
        pol_error "The offline APK has an unexpected launcher activity."
    if grep -Eq 'android\.net\.VpnService|\.CoreService|\.MainActivity|\.QuickTile|\.ConnectWidget' <<< "$manifest"; then
        pol_error "An upstream Android entry point is registered in the offline APK."
    fi
    grep -Eq 'android:allowBackup.*=\(type 0x12\)0x0$' <<< "$manifest" ||
        pol_error "The offline APK must disable application backup."
fi

out="${POL_ANDROID_ARTIFACT_DIR:-$POL_REPO_ROOT/out}"
mkdir -p "$out"
artifact_tmp="$(mktemp -d "$out/.android-artifacts.XXXXXX")"
trap 'rm -rf -- "$artifact_tmp"' EXIT
cp -- "$apk" "$artifact_tmp/$artifact"
(cd -- "$artifact_tmp" && sha256sum "$artifact" > "$artifact.sha256")
mv -- "$artifact_tmp/$artifact" "$artifact_tmp/$artifact.sha256" "$out/"
printf 'Built %s\n' "$out/$artifact"
