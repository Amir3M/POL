# Tasks

## M0 and M1 · Environment and baseline

- [x] Preserve the original repository and import Arman v1.0.19 with Git history and an upstream remote.
- [x] Audit the source, provider authorization, account and quota behavior, network design and licensing.
- [x] Provision Go, gomobile, JDK and the Android SDK/NDK in Linux.
- [ ] Verify Codespaces bootstrap and the exact Flutter toolchain.
- [x] Run upstream Go vet, Go unit tests, gVisor TUN checks and the native TUN adapter build.
- [ ] Run upstream Flutter analysis and tests, build the untouched Android APK and record package, signer and checksum.

## M2 · First POL Android build

- [ ] Apply POL package IDs, supplied logo, splash, local titles, attribution and artifact naming.
- [ ] Disable upstream service access, account collection and automatic external requests in the POL preview.
- [ ] Build and verify an installable, offline debug APK. Enable live VPN functions only after provider approval.

## M3 · Functional verification

- [ ] Obtain provider approval, POL-specific OAuth registration and the service and quota contracts.
- [ ] Implement authorized sign-in, token restoration and refresh, logout, secure storage, backup exclusions and session reset.
- [ ] Present provider-backed limited, unlimited, unknown, refresh-failed and exhausted quota states.
- [ ] Run the physical Android checklist for connectivity, sessions, splits, leaks and network transitions.

## M4 · Custom UI and diagnostics

- [ ] Build the monochrome home, locations, accounts, settings and About screens with real states and measurements.
- [ ] Implement copy, export and clear for sanitized diagnostics.

## M5 · Release candidate

- [ ] Verify the GitHub Android workflow, APK package IDs, stable debug signing and artifact checksums.
- [ ] Complete regression and physical testing, transitive license inventory and corresponding source distribution.
- [ ] Configure production signing and publish an owner-approved pre-release after the release checks pass.
