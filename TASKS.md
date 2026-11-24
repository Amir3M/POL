# Tasks

## M0 and M1 · Environment and baseline

- [x] Preserve the original repository and import Arman v1.0.19 with Git history and an upstream remote.
- [x] Audit the source, provider authorization, account and quota behavior, network design and licensing.
- [x] Provision Go, gomobile, JDK and the Android SDK/NDK in Linux.
- [x] Add the pinned Codespaces bootstrap and verify the Flutter version used for source checks.
- [ ] Verify a clean Codespaces startup and toolchain downloads.
- [x] Run upstream Go vet, Go unit tests, gVisor TUN checks and the native TUN adapter build.
- [x] Run upstream Flutter analysis and tests.
- [x] Build and inspect the untouched Android source locally with version-matched cached Flutter libraries.
- [x] Verify a clean upstream APK build with the official Flutter artifacts on GitHub Actions.

## M2 · First POL Android build

- [x] Apply POL package IDs, a vector based on the supplied logo, splash, local titles, attribution and artifact naming.
- [x] Disable upstream service access, account collection and automatic external requests in the POL preview.
- [x] Build and inspect the signed offline debug APK.
- [ ] Install and launch the APK on a physical Android device.

## M3 · Functional verification

- [ ] Obtain provider approval, POL-specific OAuth registration and the service and quota contracts.
- [ ] Implement authorized sign-in, token restoration and refresh, logout, secure storage, backup exclusions and session reset.
- [x] Remove hardcoded and aggregate quota claims from the retained account UI. Test unknown, reported unlimited and finite usage, reset dates and refresh failure with fixtures.
- [ ] Present provider-backed limited, unlimited, unknown, refresh-failed and exhausted quota states.
- [ ] Run the physical Android checklist for connectivity, sessions, splits, leaks and network transitions.

## M4 · Custom UI and diagnostics

- [ ] Build the monochrome home, locations, accounts, settings and About screens with real states and measurements.
- [x] Implement copy and export for the offline diagnostic report.
- [ ] Add and test live event logging, sanitization and log clearing after provider integration.

## M5 · Release candidate

- [x] Configure and statically validate the GitHub Android workflow.
- [x] Verify corresponding source and notice packaging for the local preview APK.
- [ ] Verify a hosted workflow and test APK updates with the owner's shared debug signing key.
- [ ] Complete regression and physical testing, transitive license inventory and corresponding source distribution.
- [ ] Configure production signing and publish an owner-approved pre-release after the release checks pass.
