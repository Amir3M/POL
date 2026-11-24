# Test report

Updated November 24, 2026. The upstream worktree is pinned to Arman VPN v1.0.19 at `492dd7f389c539790cde3d07167535d28788a0d0`.

| Check | Result |
| --- | --- |
| `go vet ./...` and `go test ./...` | Passed with Go 1.27.2. Initial module download was blocked at Google's storage redirect. Retry with the public module proxy and a direct Git fallback succeeded without changing dependencies. |
| `go vet -tags with_gvisor ./internal/tunstack/` and `go test -tags with_gvisor ./internal/tunstack/` | Passed. |
| `node --check docs/relay/cloudflare/worker.js` | Passed. This checks syntax only. |
| Upstream `hev-socks5-tunnel` `ndk-build` | Passed with NDK `30.0.16248370`, Android API 24 and the upstream JNI arguments, for arm64-v8a, armeabi-v7a and x86_64. Native ELF load segments are 16 KiB aligned. |
| `gomobile bind -target=android -androidapi 24` | Passed. Produced `core.aar` with Go JNI libraries for the three Android APK architectures and x86. |
| Flutter SDK bootstrap from the official engine artifact host | Failed with HTTP 403 in the workspace. The framework tools were rebuilt from Flutter tag `3.50.0` using a digest-verified cache from `forthecommunity/flutter:3.50.0`. The Flutter revision `ab2912035e`, engine `371f77202a` and Dart 3.14.0 matched their source pins. |
| `flutter pub get --enforce-lockfile`, `flutter analyze --no-pub`, `flutter test --no-pub` | Passed. Lockfile unchanged, analyzer reported zero issues, and all 220 Flutter tests passed on the unmodified Arman source. |
| Baseline APK assembly with the official Flutter Maven repository | The local build stopped at `checkReleaseDuplicateClasses`. The workspace proxy returned HTTP 403 for the Flutter embedding and architecture artifacts. The upstream checkout remained clean. |
| Local baseline APK assembly from unchanged source | Passed using reconstructed Flutter Maven JARs with the same cached engine Java class and native library payloads. `apksigner` verified the APK. Package `com.arman.firefoxvpn`, version `1.0.19+157`, Android minimum API 24 and target API 36, arm64, ARMv7 and x86-64. SHA-256 `314c365ba71c3eaca05680428e2c0874698e00d21b9ad84df5d15f07fff6060a`. |
| Codespaces boot and GitHub Actions | Bash syntax, devcontainer JSON and `actionlint` passed. The pinned JDK 21 devcontainer image built and ran locally as `vscode`. A fresh Codespace is untested. GitHub setup and tests passed on the second run, and APK assembly is in progress. [First hosted run](https://github.com/Amir3M/POL/actions/runs/45388671433) · [Second hosted run](https://github.com/Amir3M/POL/actions/runs/45389066235) |
| POL preview source checks | Passed Go vet, Go tests, gVisor checks, Flutter analysis and all 221 Flutter tests, including the offline preview regression test. |
| POL VPN 0.1.0 debug APK | Built locally with the same Flutter cache workaround. Verified APK signature, package `com.polvpn.app.debug`, version code `1`, label `POL VPN`, minimum API 24, target API 36, and all three ABIs. The merged manifest requests only the app's internal dynamic-receiver permission. It disables backup and exposes no upstream connection entry point. |
| POL debug checksum and signer | SHA-256 `81efe7a9b4c6b0442f7386ec80ed328722f63ece907aabce71ec15f2014c4f26`. Debug signer SHA-256 `a2ec7957ee651c464aaf978810e5613791ec1b342b23a714fbbc65a3e31bb95d`. `scripts/build-android.sh release` rejected the missing key configuration. |
| Mozilla authentication, VPN, quota and physical Android testing | Pending provider authorization and access to a physical Android device. |

The Flutter cache layer SHA-256 was `e9d087e4cd17f187261fbc60ff03a47a2805bc2c3b8e7beb2f6f601e9f87f323`. The digest verifies the OCI layer. The reconstructed JAR envelopes differ from Google's published Maven archives. Flutter warned that its next versions will raise the minimum supported Gradle, AGP and Kotlin versions. This build used upstream's pinned versions. See the [device test checklist](DEVICE_TEST_CHECKLIST.md) for installation and connectivity verification.
