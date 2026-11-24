# Test report

Updated November 24, 2026. The upstream worktree is pinned to Arman VPN v1.0.19 at `492dd7f389c539790cde3d07167535d28788a0d0`.

| Check | Result |
| --- | --- |
| `go vet ./...` and `go test ./...` | Passed with Go 1.27.2. Initial module download was blocked at Google's storage redirect. Retry with the public module proxy and a direct Git fallback succeeded without changing dependencies. |
| `go vet -tags with_gvisor ./internal/tunstack/` and `go test -tags with_gvisor ./internal/tunstack/` | Passed. |
| `node --check docs/relay/cloudflare/worker.js` | Passed. This checks syntax only. |
| Upstream `hev-socks5-tunnel` `ndk-build` | Passed with NDK `30.0.16248370`, Android API 24 and the upstream JNI arguments, for arm64-v8a, armeabi-v7a and x86_64. Native ELF load segments are 16 KiB aligned. |
| Flutter SDK bootstrap from the official engine artifact host | Failed with HTTP 403 in the workspace. Exact-version cache verification is in progress. |
| `gomobile bind`, `flutter analyze`, `flutter test` and baseline APK assembly | Results pending. |
| Codespaces boot and GitHub Actions | Pending execution. |
| Mozilla authentication, VPN, quota and physical Android testing | Pending provider authorization and access to a physical Android device. |

The Go and C checks do not establish APK installability or VPN connectivity. See the [device test checklist](DEVICE_TEST_CHECKLIST.md) for verification procedures.
