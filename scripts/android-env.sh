#!/usr/bin/env bash
# Shared Android build environment. Source this file from Bash.
POL_REPO_ROOT="${POL_REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
POL_TOOLS_DIR="${POL_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pol-vpn}"
POL_FLUTTER_VERSION=3.50.0
POL_FLUTTER_COMMIT=ab2912035e160d9cad6306df307576da6128ebdb
POL_JAVA_MAJOR=21
POL_ANDROID_API=36
POL_ANDROID_MIN_API=24
POL_BUILD_TOOLS_VERSION=36.0.0
POL_GO_VERSION="$(awk '$1 == "go" { print $2; exit }' "$POL_REPO_ROOT/core/go.mod")"
POL_GOMOBILE_VERSION="$(awk '$1 == "golang.org/x/mobile" { print $2; exit }' "$POL_REPO_ROOT/core/go.mod")"
POL_NDK_VERSION="$(sed -n 's/^[[:space:]]*ndkVersion = "\([^"]*\)".*/\1/p' "$POL_REPO_ROOT/app/android/app/build.gradle.kts")"

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$POL_TOOLS_DIR/android-sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/$POL_NDK_VERSION}"
export GOBIN="${GOBIN:-$POL_TOOLS_DIR/bin}"
export GOTOOLCHAIN=local
export FLUTTER_SUPPRESS_ANALYTICS=true

if [[ -z ${JAVA_HOME:-} ]] && command -v javac >/dev/null; then
    JAVA_HOME="$(dirname -- "$(dirname -- "$(readlink -f -- "$(command -v javac)")")")"
fi
if [[ -n ${JAVA_HOME:-} ]]; then
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
fi
for pol_go_dir in "$POL_TOOLS_DIR/go-$POL_GO_VERSION" "$POL_TOOLS_DIR/go"; do
    if [[ -x "$pol_go_dir/bin/go" && "$("$pol_go_dir/bin/go" version 2>/dev/null)" == "go version go$POL_GO_VERSION "* ]]; then
        export PATH="$pol_go_dir/bin:$PATH"
        break
    fi
done
unset pol_go_dir
for pol_flutter_dir in "$POL_TOOLS_DIR/flutter-$POL_FLUTTER_VERSION" "$POL_TOOLS_DIR/flutter"; do
    if [[ -x "$pol_flutter_dir/bin/flutter" && "$(git -C "$pol_flutter_dir" rev-parse HEAD 2>/dev/null)" == "$POL_FLUTTER_COMMIT" ]]; then
        export PATH="$pol_flutter_dir/bin:$PATH"
        break
    fi
done
unset pol_flutter_dir
export PATH="$GOBIN:$ANDROID_HOME/platform-tools:$PATH"

pol_error() {
    printf 'Error: %s\n' "$*" >&2
    return 1
}

pol_check_java() {
    local version
    if [[ ! -x "${JAVA_HOME:-}/bin/javac" ]]; then
        pol_error "Install JDK $POL_JAVA_MAJOR and set JAVA_HOME."
        return 1
    fi
    version="$("$JAVA_HOME/bin/javac" -version 2>&1 | awk '$1 == "javac" { print $2 }')"
    [[ ${version%%.*} == "$POL_JAVA_MAJOR" ]] || pol_error "Expected JDK $POL_JAVA_MAJOR, found ${version:-unknown}."
}

pol_check_go() {
    command -v go >/dev/null && [[ "$(go version 2>/dev/null)" == "go version go$POL_GO_VERSION "* ]]
}

pol_check_flutter() {
    local executable sdk
    executable="$(command -v flutter)" || return 1
    sdk="$(dirname -- "$(dirname -- "$(readlink -f -- "$executable")")")"
    [[ "$(git -C "$sdk" rev-parse HEAD 2>/dev/null)" == "$POL_FLUTTER_COMMIT" ]]
}

pol_check_mobile_tools() {
    local tool executable version
    for tool in gomobile gobind; do
        executable="$(command -v "$tool")" || return 1
        version="$(go version -m "$executable" | awk '$1 == "mod" && $2 == "golang.org/x/mobile" { print $3 }')"
        [[ "$version" == "$POL_GOMOBILE_VERSION" ]] || return 1
    done
}

pol_check_ndk() {
    [[ -x "$ANDROID_NDK_HOME/ndk-build" && -f "$ANDROID_NDK_HOME/source.properties" ]] || return 1
    [[ "$(sed -n 's/^Pkg.Revision[[:space:]]*=[[:space:]]*//p' "$ANDROID_NDK_HOME/source.properties")" == "$POL_NDK_VERSION" ]]
}

# Hosted runners can export a path to a different preinstalled NDK. Reuse an
# override only when it already points to the version required by this checkout.
if ! pol_check_ndk; then
    export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$POL_NDK_VERSION"
fi

pol_require_sdk() {
    [[ -f "$ANDROID_HOME/platforms/android-$POL_ANDROID_API/android.jar" ]] &&
        [[ -x "$ANDROID_HOME/build-tools/$POL_BUILD_TOOLS_VERSION/apksigner" ]] &&
        pol_check_ndk ||
        pol_error "Install the pinned Android SDK packages with scripts/setup-android.sh."
}

pol_require_language_tools() {
    pol_check_java
    pol_check_go || pol_error "Go $POL_GO_VERSION is required. Run scripts/setup-android.sh."
    pol_check_flutter || pol_error "Flutter $POL_FLUTTER_VERSION is required. Run scripts/setup-android.sh."
}

pol_pub_get() {
    flutter pub get --offline --enforce-lockfile || flutter pub get --enforce-lockfile
}
