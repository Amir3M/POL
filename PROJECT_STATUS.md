# Project status

Updated November 24, 2026.

**Current phase:** M2 offline Android preview. M3 live functionality depends on provider approval.

**Completed:** Imported Arman VPN v1.0.19 with Git history and built the untouched baseline on GitHub Actions. Added pinned Linux, Codespaces and GitHub Actions builds. Added POL's package IDs, logo, splash, offline status, About and diagnostics. Corrected the retained account UI to show reported quota per account and distinguish unknown usage.

**Last verified source:** POL Android preview `39343a6beb95e10310baa8116261be47066e50bd`, based on Arman `492dd7f389c539790cde3d07167535d28788a0d0`. Go vet, Go tests, gVisor tests, Flutter analysis and all 223 Flutter tests passed on the POL preview source.

**Build status:** POL VPN 0.1.1 debug built locally in `out/` for Android API 24+ with package ID `com.polvpn.app.debug`. Signature, checksum, architecture coverage and the offline manifest passed inspection. The app includes the Git build ID and is signed by the same local debug certificate as 0.1.0. Local APK assembly used matching Flutter library bytes recovered from the SDK cache after the official Maven host returned HTTP 403. The hosted baseline built with the official Flutter dependencies. [Baseline run](https://github.com/Amir3M/POL/actions/runs/45389066235) · [Draft foundation PR and preview checks](https://github.com/Amir3M/POL/pull/1/checks)

**Blockers:** Mozilla authorization for a POL OAuth client, the VPN service contract and any relay use. Physical device installation, launch and live tests remain pending. GitHub debug artifact uploads require a shared debug signing identity. Production distribution also requires a release signing identity and a verified notices package.

**Preview publication:** The exact `pol-v0.1.1-preview` tag points to `33dfaaca196cf9149fdd93a7de1b35e98a30c3f9`. The official PR build passed its artifact checks. The tag run stopped at signing because the repository signing secrets were unavailable. The protected copy of the previous debug key is available in the cloud workspace. `api.github.com` remains blocked by the workspace policy, and the direct APK URL returns HTTP 404. [Official PR build](https://github.com/Amir3M/POL/actions/runs/45395077041) · [Tag run](https://github.com/Amir3M/POL/actions/runs/45395945368)

**Next:** Allow GitHub API access to provision the shared debug signing secrets, rerun the existing tag and verify the public download. For live connectivity, obtain the POL-specific provider authorization and reuse the verified Android connection path in a separate test artifact. See the [connection report](docs/ANDROID_CONNECTION_PATH.md), [tasks](TASKS.md) and [test report](docs/TEST_REPORT.md).
