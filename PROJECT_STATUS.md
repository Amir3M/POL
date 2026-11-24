# Project status

Updated November 24, 2026.

**Current phase:** M2 offline Android preview. M3 live functionality depends on provider approval.

**Completed:** Imported Arman VPN v1.0.19 with Git history. Audited source, licensing and provider authorization. Added reproducible build configuration for Linux, Codespaces and GitHub Actions. Added POL's package IDs, launcher, splash, offline status and About screen.

**Last verified source:** POL Android preview `94349041023819417003090af6a305d0b3eeb2b6`, based on Arman `492dd7f389c539790cde3d07167535d28788a0d0`. Go vet, Go tests, gVisor tests, Flutter analysis and all 221 Flutter tests passed on the POL preview source.

**Build status:** POL VPN 0.1.0 debug built locally for Android API 24+ with package ID `com.polvpn.app.debug`. Signature, checksum, architecture coverage and the offline manifest passed inspection. Local APK assembly used matching Flutter library bytes recovered from the SDK cache after the official Maven host returned HTTP 403. The hosted baseline with official Flutter dependencies is in progress. [Baseline run](https://github.com/Amir3M/POL/actions/runs/45389066235) · [Draft foundation PR](https://github.com/Amir3M/POL/pull/1)

**Blockers:** Mozilla authorization for a POL OAuth client, the VPN service contract and any relay use. Physical device installation, launch and live tests remain pending. GitHub debug artifact uploads require a shared debug signing identity. Production distribution also requires a release signing identity and a verified notices package.

**Next:** Verify the official-artifact hosted builds and smoke-test the preview on a physical Android phone. Resume authorized authentication and quota integration once the POL-specific provider details are available. See [Tasks](TASKS.md), the [test report](docs/TEST_REPORT.md) and the [CI instructions](docs/RELEASING.md).
