# Android builds and release candidates

The Android workflow currently verifies Arman VPN v1.0.19 at commit `492dd7f389c539790cde3d07167535d28788a0d0` for pull requests, pushes to `main` and manual **baseline** runs. The run summary records the checksum of the upstream release variant built with the runner's local Android debug key.

The POL options below require the independent application ID and signing configuration. Once those are in place, use POL debug as the default. Debug builds with the configured signing key can upload an APK and its SHA-256 checksum to the workflow run. Pull requests use a temporary runner key for build verification.

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

The debug application ID is `com.polvpn.app.debug`. Keep the signing key and application ID consistent across updates. Increment the build number in `app/pubspec.yaml` for a new distributed version.

## Prepare a release candidate

Set `version: X.Y.Z+BUILD` in `app/pubspec.yaml`, with a build number higher than the previous published APK, and add a corresponding `## [X.Y.Z]` section to `CHANGELOG.md`. Manually dispatch the **Android** workflow, choose **release**, and enter `X.Y.Z`. Download the tested, signed artifact and verify it with `sha256sum --check pol-vpn-release.apk.sha256`.

Use the APK from the verified workflow run for physical device testing. After the release checks pass and the project has service authorization, the owner can publish a GitHub prerelease from the exact workflow commit, with the APK, checksum, corresponding source archive, license materials and generated release notes. Use a POL-specific tag such as `pol-vX.Y.Z-rc.1` to distinguish it from upstream tags. Link the corresponding source tree and repeatable build instructions in the release. Promote to stable only after reviewing the device test report and license compliance.
