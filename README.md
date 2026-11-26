# AMiR VPN

AMiR VPN brings a new visual identity to the public source of [Arman VPN v1.0.19](https://github.com/armanlife/arman-vpn-client/releases/tag/v1.0.19). The Android, Windows, and Linux apps share the rounded logo, AMiR VPN name, and the light-to-black gradient on the home screen.

| Platform | Latest stable downloads |
| --- | --- |
| Android 7 and above | [Signed APK](https://github.com/Amir3M/POL/releases/latest/download/amir-vpn-android.apk) |
| Windows x64 | [Installer](https://github.com/Amir3M/POL/releases/latest/download/amir-vpn-windows-setup-x64.exe) or [portable ZIP](https://github.com/Amir3M/POL/releases/latest/download/amir-vpn-windows-x64.zip) |
| Linux x64 | [Debian / Ubuntu package](https://github.com/Amir3M/POL/releases/latest/download/amir-vpn-linux-x64.deb) or [portable archive](https://github.com/Amir3M/POL/releases/latest/download/amir-vpn-linux-x64.tar.gz) |

The standalone Android **1.0.2** update is available from the [Android release](https://github.com/Amir3M/POL/releases/tag/v1.0.2). Android 1.0.1 users can download it once to migrate to the Android-specific stable update search.

Use **About → Check for updates** to find a newer stable AMiR VPN release in this repository and open the download for your platform. Install the package after download. To move from an earlier preview to v1, download the stable package from this table once. On Debian or Ubuntu, install the downloaded package with `sudo apt install ./amir-vpn-linux-x64.deb`, then open AMiR VPN from the app menu or run `amir-vpn`. For the portable download, extract the archive and run `./arman-vpn` from the `amir-vpn` directory.

The [latest release](https://github.com/Amir3M/POL/releases/latest) contains checksums, corresponding source, and dependency notices.

## Share Proxy on Android

Open the **Quick VPN mode switch** on Home and tap **Share Proxy**. New Android installations show the switch by default. Existing installations can enable it in **Settings → General → Quick VPN mode switch**. The first activation asks for consent. Add your Mozilla account first if the app has no account yet. The card shows an active SOCKS5 endpoint once the VPN upstream passes the existing connection test.

The preset keeps the ordinary proxy on loopback. It binds the shared listener to one verified Wi-Fi or hotspot IPv4 address and accepts TCP clients from that address's local subnet. Hotspot discovery depends on Android exposing the tethered Wi-Fi interface. To use another verified address, select it in **Connection details**. The app changes the listener and disconnects clients at the old address. Switching modes or stopping the connection closes the shared listener and its sessions. Android's service keeps watching available endpoints while running. Sharing starts disabled after process restart.

Use the private IPv4 address and configured port with an authenticated SOCKS5 client. Generated credentials are held in memory. The existing configured local proxy login is reused when available. The **Generate new credentials** action gives the shared listener a new in-memory login without changing ordinary proxy settings. A QR or a Telegram `tg://socks` link can contain the password. Share it only with people you trust. SOCKS5 authentication by itself does not encrypt the local connection.

Share Proxy forwards TCP through the VPN upstream and fails closed when that upstream cannot carry the request. SOCKS5 UDP and connected-device statistics are unavailable in this release. Wi-Fi and hotspot behavior, sleep, and traffic over a real Mozilla account should be checked on physical devices.

The connection and sign-in implementation comes from the public Arman VPN source at [492dd7f](https://github.com/armanlife/arman-vpn-client/commit/492dd7f389c539790cde3d07167535d28788a0d0). The Windows installer uses a separate application registration and folder. The optional desktop TUN service retains its upstream identity.

- [Arman VPN source and documentation](https://github.com/armanlife/arman-vpn-client/tree/v1.0.19)
- [GNU General Public License v3](LICENSE)
