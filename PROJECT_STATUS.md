# Project status

Updated November 24, 2026.

**Current phase:** M0 development environment and M1 baseline Android build.

**Completed:** Imported the full Arman VPN v1.0.19 history into the existing POL repository. Finished the initial source, license and provider authorization audit. Provisioned Go 1.27.2, JDK 21, Android SDK API 36, build-tools 36.0.0 and NDK 30.0.16248370 in the Linux workspace.

**Last verified source:** Arman VPN `492dd7f389c539790cde3d07167535d28788a0d0`. The upstream Go tests and vet checks passed, including the gVisor TUN suite. The native Android TUN adapter built successfully for all three supported ABIs.

**Build status:** Baseline APK verification is in progress. The official Flutter binary host returned HTTP 403 in this environment. An exact-version Flutter cache is being checked independently.

**Blockers:** Public Mozilla documentation does not grant POL access to Firefox's built-in VPN. Live sign-in and tunnel tests require an approved OAuth client, the approved service contract and applicable relay permissions. No physical Android device is connected. Production distribution requires an owner's release signing configuration and a verified notices package.

**Next:** Verify the pinned Flutter toolchain, run the upstream Flutter checks and assemble the unmodified Android APK. After the baseline milestone, apply POL branding and enforce the Android provider gate. See [Tasks](TASKS.md) and the [test report](docs/TEST_REPORT.md).
