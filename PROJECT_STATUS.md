# Project status

Updated November 24, 2026.

**Current phase:** M3 controlled Android tunnel testing. The M2 offline preview is published. Live functionality depends on provider approval.

**Completed:** Imported Arman VPN v1.0.19 with Git history and built the untouched baseline on GitHub Actions. Added pinned Linux, Codespaces and GitHub Actions builds. Added POL's package IDs, logo, splash, offline status, About and diagnostics. Corrected the retained account UI to show reported quota per account and distinguish unknown usage.

**Last verified source:** POL VPN Tunnel Test `46c6e95fc0e1cc3d308f048cb8bc5a8186bf40fd`, based on Arman `492dd7f389c539790cde3d07167535d28788a0d0`. Hosted Go, Flutter and Android emulator tests passed. [Tagged run](https://github.com/Amir3M/POL/actions/runs/45418550016)

**Build status:** GitHub Actions built POL VPN Tunnel Test `0.1.2+3` using pinned official dependencies. The public APK uses `com.polvpn.app.debug`, Android API 24+ and the established debug certificate. ARM64, ARMv7 and x86-64 are included. The APK is 107,677,616 bytes. SHA-256 `8f6e24af28e0de73b98dbf9495c72b23b0825e7909329280a42c49ef4f3c19c7`. [APK download](https://github.com/Amir3M/POL/releases/download/pol-v0.1.2-tunnel-test/pol-vpn-debug.apk) · [Tunnel test prerelease](https://github.com/Amir3M/POL/releases/tag/pol-v0.1.2-tunnel-test)

**Blockers:** Mozilla authorization for a POL OAuth client, the VPN service contract and any relay use. Physical device installation, launch and live tests remain pending. Production distribution requires a separate release signing identity.

**Preview publication:** The `pol-v0.1.1-preview` tag points to `33dfaaca196cf9149fdd93a7de1b35e98a30c3f9`. GitHub Actions attempt 2 built and published the prerelease using official dependencies and the established debug certificate. The public APK downloaded successfully and matched the signed build and published checksum. The release also includes matching source and notices. [APK download](https://github.com/Amir3M/POL/releases/download/pol-v0.1.1-preview/pol-vpn-debug.apk) · [Prerelease](https://github.com/Amir3M/POL/releases/tag/pol-v0.1.1-preview) · [Tag run](https://github.com/Amir3M/POL/actions/runs/45395945368)

**Tunnel test:** The Android debug build reuses `runAndroid()`, the VPN permission flow, the Android TUN adapter and Go proxy. The Android 15 emulator restored an encrypted synthetic session after process exit and the signed build 3 to 4 update, renewed it, transferred 256 KiB in each direction from the shell UID, disconnected and confirmed persistent logout. The public APK, checksum, corresponding source and notices all downloaded and passed verification. [Device test checklist](docs/DEVICE_TEST_CHECKLIST.md#controlled-tunnel-test)

**Next:** Run the controlled checklist on a physical phone while Arman is closed. For live connectivity, obtain POL-specific provider authorization and test separately. [Connection report](docs/ANDROID_CONNECTION_PATH.md) · [Tasks](TASKS.md) · [Test report](docs/TEST_REPORT.md)
