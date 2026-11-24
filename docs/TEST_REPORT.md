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
| Baseline APK assembly | Gradle build in progress. |
| Codespaces boot and GitHub Actions | Bash syntax, devcontainer JSON and `actionlint` passed. Hosted runs pending. The local container build hit HTTP 403 while pulling the Microsoft image. |
| Mozilla authentication, VPN, quota and physical Android testing | Pending provider authorization and access to a physical Android device. |

The Flutter cache layer SHA-256 was `e9d087e4cd17f187261fbc60ff03a47a2805bc2c3b8e7beb2f6f601e9f87f323`. The digest verifies the OCI layer. Google-hosted artifacts require independent verification. See the [device test checklist](DEVICE_TEST_CHECKLIST.md) for installation and connectivity verification.
