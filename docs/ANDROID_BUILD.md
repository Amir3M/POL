# Android development

Open this repository in a GitHub Codespace. The devcontainer uses JDK 21 and runs `scripts/setup-android.sh` once the checkout is ready. A 4-core, 16 GB Codespace is sufficient. The setup installs Android tooling and Flutter's Android artifacts. The first build or test resolves the project dependencies into the standard Gradle, pub, and Go caches.

For an existing x86_64 Linux environment with JDK 21, run the same commands from the repository root:

```sh
scripts/setup-android.sh
scripts/test-android.sh
scripts/build-android.sh debug
```

On a bare Linux environment, install Git, curl, jq, xz, unzip, util-linux, and libGL for Flutter's host test engine. Set `JAVA_HOME` if `javac` is outside `PATH`. The script accepts Android SDK licenses when it needs to install components.

| Component | Version |
| --- | --- |
| JDK | 21 |
| Flutter | 3.50.0, commit `ab2912035e160d9cad6306df307576da6128ebdb` |
| Go and gomobile | `core/go.mod` |
| Android API | 36 compile and target, 24 minimum |
| SDK Command-line Tools | 21.0 |
| Android SDK Build Tools | 36.0.0 |
| NDK | 30.0.16248370 |
| Gradle / Android Gradle Plugin | 9.3.1 / 9.1.1 |

Setup reuses matching tools and installed SDK packages. It installs missing tools into `${XDG_CACHE_HOME:-$HOME/.cache}/pol-vpn`. Use `POL_TOOLS_DIR` for an alternate cache directory or `ANDROID_HOME` for an existing SDK. Flutter supplies the untracked Gradle wrapper launchers and JAR when building. The tracked `app/android/gradle/wrapper/gradle-wrapper.properties` sets the distribution version.

The build binds the Go mobile package into a local AAR, then builds one universal APK with ARMv7, ARM64 and x86-64 native libraries. The script verifies the APK signature and writes the APK and its SHA-256 file under `out/`. Override the output directory with `POL_ANDROID_ARTIFACT_DIR`.

## Upstream baseline

Run the scripts from the POL checkout and build the original sources in a separate worktree:

```sh
git fetch upstream --tags
git worktree add --detach ../arman-baseline 492dd7f389c539790cde3d07167535d28788a0d0
POL_REPO_ROOT="$(realpath ../arman-baseline)" scripts/test-android.sh
POL_REPO_ROOT="$(realpath ../arman-baseline)" scripts/build-android.sh baseline
```

This mode uses the original application ID and release build variant. Arman VPN signs a checkout without release properties with the local Android debug key. The result is `../arman-baseline/out/arman-vpn-baseline.apk`. To inspect the baseline worktree after a build, use `git -C ../arman-baseline status --short`.

## Release build

Use `scripts/build-android.sh release` with an owner-controlled release keystore configured in the gitignored `app/android/key.properties`. The build script expects a key configuration file before building and verifies the signed APK. See the release process before distributing production artifacts.
