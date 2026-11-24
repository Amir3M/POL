# License compliance

## Source and assets

POL is a modified fork of Arman VPN `v1.0.19` at `492dd7f389c539790cde3d07167535d28788a0d0`. The upstream root license is the GNU General Public License version 3. Upstream labels its container distribution `GPL-3.0-only`. Preserve the full text, file-level copyright notices, upstream credit and source history. Keep a dated record of POL changes and identify the exact source revision for each distributed APK. [GPL-3.0 text](../LICENSE) · [Upstream license identifier](https://github.com/armanlife/arman-vpn-client/blob/v1.0.19/.github/workflows/docker.yml#L148) · [Upstream release](https://github.com/armanlife/arman-vpn-client/releases/tag/v1.0.19)

| Bundled source or asset | License and relevant source files |
| --- | --- |
| hev-socks5-tunnel, SOCKS5 core, hev-task-system, YAML library | MIT. Preserve the license in [tunnel](../app/android/hev-socks5-tunnel/LICENSE), [SOCKS5 core](../app/android/hev-socks5-tunnel/src/core/LICENSE), [task system](../app/android/hev-socks5-tunnel/third-part/hev-task-system/LICENSE) and [YAML](../app/android/hev-socks5-tunnel/third-part/yaml/LICENSE). |
| lwIP | BSD three-clause. Its binary redistribution conditions require the notice, conditions and disclaimer in materials supplied with the distribution. [License](../app/android/hev-socks5-tunnel/third-part/lwip/LICENSE) |
| flag-icons | MIT with Panayiotis Lipiridis copyright. [Flutter assets](../app/assets/flags/LICENSE) · [Core dashboard assets](../core/internal/service/web/flags/LICENSE) |
| Inter and Vazirmatn | SIL Open Font License 1.1. Include copyright and license texts and follow the naming conditions if modifying fonts. [Inter](../app/assets/fonts/Inter/OFL.txt) · [Vazirmatn](../app/assets/fonts/OFL.txt) |
| Flutter/Dart, Android libraries and Go modules | The notice archive includes Flutter notices from the APK, Go licenses from the Android build graph, and the resolved Android runtime inventory with Apache-2.0 and embedded license texts. [Dart dependencies](../app/pubspec.lock) · [Android license inventory](licenses/android-runtime-apache-2.0.txt) · [Go dependencies](../core/go.mod) |

Also review per-file notices in the native tree, files embedded in the Go core such as the web dashboard and certificate bundle, and any added or downloaded assets. Record the provenance of POL's supplied logo in the release's source record.

## Binary distribution

Complete these checks for each public debug, pre-release or production APK.

1. Attach the source archive or an immutable link to the exact Corresponding Source alongside the APK, in accordance with GPL section 6. Include POL changes, any shipped native sources or patches, and the scripts and configuration needed to build and install the binary. Apply the GPL's Installation Information requirement when section 6 makes it applicable.
2. Include the GPL text and applicable copyright, license and disclaimer notices for the actual binary and assets. Link to the Corresponding Source and attribution from the app's About screen and release notes. Preserve upstream notices in the source archive.
3. Verify the APK version, source commit, dependency lockfiles and checksums against the release artifacts. Keep credentials, signing keys and local account data outside the source archive.
4. Use the POL VPN identity and independent branding. Credit Arman VPN and describe any Mozilla integration accurately. The GPL covers software distribution. Mozilla's service eligibility and trademark rules apply independently.

The Android artifact packager includes Flutter notices, vendored native and asset notices, and mobile Go dependency licenses. It resolves the exact Android variant's Maven runtime dependencies from the build cache and includes the inventory, attribution and embedded notices from its JARs and AARs. Review and update the Android license inventory before shipping a dependency or version outside the audited set. [GPL section 6](https://www.gnu.org/licenses/gpl-3.0.en.html#section6) · [Mozilla trademark policy](https://www.mozilla.org/en-US/foundation/trademarks/policy/)
