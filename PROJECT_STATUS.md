# Project status

Updated November 24, 2026.

**Current phase:** M0 development environment and M1 baseline Android build.

**Completed:** Imported the full Arman VPN v1.0.19 history into the existing POL repository. Finished the initial source, license and provider authorization audit. Added the pinned Linux and Codespaces build setup and the Android Actions workflow. Provisioned Go 1.27.2, JDK 21, Android SDK API 36, build-tools 36.0.0 and NDK 30.0.16248370 in the Linux workspace.

**Last verified source:** Arman VPN `492dd7f389c539790cde3d07167535d28788a0d0`. Upstream Go tests and vet checks passed, including the gVisor TUN suite. Go mobile bindings and the native Android TUN adapter built. Flutter analysis and all 220 tests passed.

**Build status:** Baseline APK assembly is in progress. The official Flutter binary host returned HTTP 403 in this environment. The source checks used a matching Flutter artifact cache from a digest-verified OCI layer.

**Blockers:** Public Mozilla documentation does not grant POL access to Firefox's built-in VPN. Live sign-in and tunnel tests require an approved OAuth client, the approved service contract and applicable relay permissions. No physical Android device is connected. Production distribution requires an owner's release signing configuration and a verified notices package.

**Next:** Assemble the unmodified Android APK, then apply POL branding and enforce the Android provider gate. See [Tasks](TASKS.md), the [test report](docs/TEST_REPORT.md) and the [CI instructions](docs/RELEASING.md).
