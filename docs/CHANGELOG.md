# Changelog

## 1.0.3

- Updated the public Arman VPN connection core to v1.0.20 on Android, Windows, and Linux. It refreshes transport selection when the network changes and improves retry behavior and location latency tests.
- Integrated the core's local data usage counters and API. The AMiR app continues to show its existing account quota view.
- Retained the Android regional routing lists, Share Proxy, and the AMiR VPN release source for app updates.

## 1.0.2 — Android

- Added Share Proxy as a fourth option in the Android quick mode panel, with a first-use confirmation and protected SOCKS5 access.
- Added endpoint selection, network status, connection details, credential rotation, QR codes, and Android sharing.
- New Android installations show the quick mode panel by default. Existing installations keep their selection.
- The Android updater looks for the newest stable release containing an Android package. Desktop packages remain on the existing stable release.

## 1.0.1

- Corrected Linux window rendering and added a Debian/Ubuntu package.
