#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

if [[ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]]; then
    pol_error "This setup script provisions an x86_64 Linux Android toolchain."
    exit 1
fi
pol_check_java
mkdir -p "$POL_TOOLS_DIR"
exec 9>"$POL_TOOLS_DIR/setup.lock"
flock 9
setup_tmp="$(mktemp -d "$POL_TOOLS_DIR/.setup.XXXXXX")"
trap 'rm -rf -- "$setup_tmp"' EXIT

download() {
    curl --fail --location --retry 3 --silent --show-error --output "$2" "$1"
}

if ! pol_check_go; then
    go_archive="go$POL_GO_VERSION.linux-amd64.tar.gz"
    go_sha256="$(curl --fail --location --retry 3 --silent --show-error 'https://go.dev/dl/?mode=json&include=all' |
        jq -er --arg archive "$go_archive" '[.[].files[] | select(.filename == $archive) | .sha256] | first')"
    download "https://go.dev/dl/$go_archive" "$setup_tmp/$go_archive"
    printf '%s  %s\n' "$go_sha256" "$setup_tmp/$go_archive" | sha256sum --check
    tar -xzf "$setup_tmp/$go_archive" -C "$setup_tmp"
    # Keep other installed Go versions in a shared tool directory.
    mv -T -- "$setup_tmp/go" "$POL_TOOLS_DIR/go-$POL_GO_VERSION"
    export PATH="$POL_TOOLS_DIR/go-$POL_GO_VERSION/bin:$PATH"
fi

if ! pol_check_flutter; then
    git clone --depth 1 --branch "$POL_FLUTTER_VERSION"         https://github.com/flutter/flutter.git "$setup_tmp/flutter"
    [[ "$(git -C "$setup_tmp/flutter" rev-parse HEAD)" == "$POL_FLUTTER_COMMIT" ]] ||
        pol_error "Flutter tag $POL_FLUTTER_VERSION differs from the pinned commit."
    mv -T -- "$setup_tmp/flutter" "$POL_TOOLS_DIR/flutter-$POL_FLUTTER_VERSION"
    export PATH="$POL_TOOLS_DIR/flutter-$POL_FLUTTER_VERSION/bin:$PATH"
fi

if ! pol_check_mobile_tools; then
    go install "golang.org/x/mobile/cmd/gomobile@$POL_GOMOBILE_VERSION"         "golang.org/x/mobile/cmd/gobind@$POL_GOMOBILE_VERSION"
fi

sdk_packages=()
[[ -x "$ANDROID_HOME/platform-tools/adb" ]] || sdk_packages+=("platform-tools")
[[ -f "$ANDROID_HOME/platforms/android-$POL_ANDROID_API/android.jar" ]] ||
    sdk_packages+=("platforms;android-$POL_ANDROID_API")
[[ -x "$ANDROID_HOME/build-tools/$POL_BUILD_TOOLS_VERSION/apksigner" ]] ||
    sdk_packages+=("build-tools;$POL_BUILD_TOOLS_VERSION")
if ! pol_check_ndk; then
    sdk_packages+=("ndk;$POL_NDK_VERSION")
fi

if (( ${#sdk_packages[@]} )); then
    sdkmanager="$ANDROID_HOME/cmdline-tools/21.0/bin/sdkmanager"
    if [[ ! -x "$sdkmanager" ]]; then
        android_cli_url=https://dl.google.com/android/repository/commandlinetools-linux-15641748_latest.zip
        android_cli_sha1=63523a02a975a81102238566f2a16c057d52301e
        download "$android_cli_url" "$setup_tmp/android-cli.zip"
        printf '%s  %s\n' "$android_cli_sha1" "$setup_tmp/android-cli.zip" | sha1sum --check
        unzip -q "$setup_tmp/android-cli.zip" -d "$setup_tmp"
        mkdir -p "$ANDROID_HOME/cmdline-tools"
        mv -T -- "$setup_tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/21.0"
    fi
    "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses < <(yes) >/dev/null
    "$sdkmanager" --sdk_root="$ANDROID_HOME" --install "${sdk_packages[@]}"
fi

pol_require_language_tools
pol_check_mobile_tools || pol_error "Could not verify gomobile and gobind at $POL_GOMOBILE_VERSION."
pol_require_sdk
flutter precache --android
printf 'Android toolchain ready (JDK %s, Flutter %s, Go %s, SDK %s, NDK %s).\n'     "$POL_JAVA_MAJOR" "$POL_FLUTTER_VERSION" "$POL_GO_VERSION" "$POL_ANDROID_API" "$POL_NDK_VERSION"
