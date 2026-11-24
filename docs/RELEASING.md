# Android builds and release candidates

The Android workflow builds and tests POL debug on pull requests and pushes to `main`. Pull requests use a temporary runner key for build verification. A main-branch push with the configured shared debug signing key can upload the APK and checksum. A manual **baseline** run verifies Arman VPN v1.0.19 at commit `492dd7f389c539790cde3d07167535d28788a0d0`. Its run summary records the checksum of the upstream release variant built with the runner's local Android debug key.

## Signing keys

Keep the keystores and a backup outside the repository. Use one key for debug and a separate key for production. GitHub Actions expects a PKCS12 keystore with the same password for the store and key.

| Build | Alias | GitHub Actions secrets |
| --- | --- | --- |
| Debug | `debug` | `POL_ANDROID_DEBUG_KEYSTORE_BASE64`, `POL_ANDROID_DEBUG_KEYSTORE_PASSWORD` |
| Release | `release` | `POL_ANDROID_RELEASE_KEYSTORE_BASE64`, `POL_ANDROID_RELEASE_KEYSTORE_PASSWORD` |

Store the base64 representation of the keystore file in the first secret and its password in the second. The workflow verifies that the APK package ID, version and signing certificate match the selected build.

For local builds, use `app/android/pol-debug.properties` for the shared debug key and `app/android/key.properties` for the production key. Both files take `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Use an absolute path for `storeFile`. Without a configured shared debug key, local development uses the standard Android debug keystore on that machine. An APK signed with that local key can update only a previous installation signed with the same key.

## Download a debug APK

Open **Actions → Android → Run workflow**, choose **debug**, and run the workflow on the intended branch. Open the finished run and extract the APK and checksum from **Artifacts**. In the extracted folder, run `sha256sum --check pol-vpn-debug.apk.sha256` before installation. The artifact also includes an archive of the exact corresponding source, a source URL and license materials. Keep those files available when distributing the APK.

The debug application ID is `com.polvpn.app.debug`. Keep the signing key and application ID consistent across updates. Increment the build number in `app/pubspec.yaml` for a new distributed version. The build includes its Git revision in the offline diagnostics report. The source archive and dependency notices ship alongside uploaded APKs.

## Publish an offline preview

The repository owner starts publication by creating a fresh `pol-vX.Y.Z-preview` tag on the approved commit, including a commit on the draft PR branch. The tag version must match `app/pubspec.yaml`. Use a higher version and build number for each subsequent preview.

```sh
git tag pol-vX.Y.Z-preview APPROVED_COMMIT
git push origin refs/tags/pol-vX.Y.Z-preview
```

The tag workflow builds with official pinned dependencies, runs tests, verifies the package, signature and checksum, packages notices and matching source, and uploads an Actions artifact. A separate job compares the downloaded GitHub Release assets to that artifact before publishing a prerelease. Tag approval is independent of the draft PR. Each preview is labeled offline and excluded from GitHub's latest stable release selection.

The established debug certificate SHA-256 is `a2ec7957ee651c464aaf978810e5613791ec1b342b23a714fbbc65a3e31bb95d`. Its protected PKCS12 copy uses the `debug` alias. Installations signed with this certificate can update in place. Android requires uninstalling previews signed by a different certificate before installing this one, which removes that app's local data. The preview workflow checks the certificate before building. Review the workflow pin and document the update impact before any signing-key rotation.

## Publish a controlled tunnel test

Build locally with `scripts/build-android.sh tunnel-test`. To package source and notices for that APK, set `POL_TUNNEL_TEST=1` when running `scripts/package-android-source.sh out/pol-vpn-debug.apk`. This selects the test-only Android manifest, Flutter entry path and Go build tag together. A normal debug build continues to use the offline preview.

After checks pass for the approved commit, increment the version and build number if needed and push a fresh tag matching the version in `app/pubspec.yaml`.

```sh
git tag pol-vX.Y.Z-tunnel-test APPROVED_COMMIT
git push origin refs/tags/pol-vX.Y.Z-tunnel-test
```

The tag workflow verifies the build and signer and runs the test on an Android emulator. The emulator checks session restoration after process exit and after installing a same-signer APK one build number higher. That APK is used only during CI. The workflow verifies transfer in both directions from Android's shell UID, packages the four release assets and publishes a separate **Tunnel Test** prerelease. The test uses `com.polvpn.app.debug` and the established debug certificate so it can update the offline preview in place. Use the [controlled tunnel checklist](DEVICE_TEST_CHECKLIST.md#controlled-tunnel-test) for device verification.

## First authorized direct build

The draft version `0.1.3+4` reserves a build number above published tunnel test `0.1.2+3`. The existing offline and tunnel-test build modes already check the application ID. The signed tunnel-test CI job checks the established certificate. The current manifest and launch path gate live activity.

Confirm the approved public native OAuth registration, exact Android callback, refresh contract, Guardian entitlement and allowed H2 egress before wiring an online build. The browser flow should use the registered callback and the isolated Keystore store. CoreService can keep the existing TUN path when the Go daemon uses the approved direct pass source for both startup and renewal. Use sanitized Diagnostics and test the approved host contract, signed update and traffic. Publish a signed experimental prerelease with checksum, corresponding source and notices only after the authorized build passes CI. [Connection audit](ANDROID_CONNECTION_PATH.md#direct-guardian-first-test)

## Prepare a release candidate

Set `version: X.Y.Z+BUILD` in `app/pubspec.yaml`, with a build number higher than the previous published APK, and add a corresponding `## [X.Y.Z]` section to `CHANGELOG.md`. Manually dispatch the **Android** workflow, choose **release**, and enter `X.Y.Z`. Download the tested, signed artifact and verify it with `sha256sum --check pol-vpn-release.apk.sha256`.

Use the APK from the verified workflow run for physical device testing. After the release checks pass and the project has service authorization, the owner can publish a GitHub prerelease from the exact workflow commit, with the APK, checksum, corresponding source archive, license materials and generated release notes. Use a POL-specific tag such as `pol-vX.Y.Z-rc.1` to distinguish it from upstream tags. Link the corresponding source tree and repeatable build instructions in the release. Promote to stable only after reviewing the device test report and license compliance.
