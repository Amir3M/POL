# Project status

Updated November 24, 2026.

**Current phase:** M2 offline Android preview. M3 live functionality depends on provider approval.

**Completed:** Imported Arman VPN v1.0.19 with Git history and built the untouched baseline on GitHub Actions. Added pinned Linux, Codespaces and GitHub Actions builds. Added POL's package IDs, logo, splash, offline status, About and diagnostics. Corrected the retained account UI to show reported quota per account and distinguish unknown usage.

**Last verified source:** POL Android preview `39343a6beb95e10310baa8116261be47066e50bd`, based on Arman `492dd7f389c539790cde3d07167535d28788a0d0`. Go vet, Go tests, gVisor tests, Flutter analysis and all 223 Flutter tests passed on the POL preview source.

**Build status:** POL VPN 0.1.1 debug built locally in `out/` for Android API 24+ with package ID `com.polvpn.app.debug`. Signature, checksum, architecture coverage and the offline manifest passed inspection. The app includes the Git build ID and is signed by the same local debug certificate as 0.1.0. Local APK assembly used matching Flutter library bytes recovered from the SDK cache after the official Maven host returned HTTP 403. The hosted baseline built with the official Flutter dependencies. [Baseline run](https://github.com/Amir3M/POL/actions/runs/45389066235) · [Draft foundation PR and preview checks](https://github.com/Amir3M/POL/pull/1/checks)

**Blockers:** Mozilla authorization for a POL OAuth client, the VPN service contract and any relay use. Physical device installation, launch and live tests remain pending. GitHub debug artifact uploads require a shared debug signing identity. Production distribution also requires a release signing identity and a verified notices package.

**Next:** Install or update the preview on a physical Android phone, then test offline launch, diagnostics copy and export. Configure the owner's shared debug signing key for repeatable GitHub downloads. Resume authorized authentication and quota integration once the POL-specific provider details are available. See [Tasks](TASKS.md), the [test report](docs/TEST_REPORT.md) and the [CI instructions](docs/RELEASING.md).
