# POL VPN architecture

POL uses the Arman VPN Android stack. The imported source is `v1.0.19` at `492dd7f389c539790cde3d07167535d28788a0d0`. The source map below identifies the interfaces to preserve when changing branding or screens. [Upstream audit](UPSTREAM_AUDIT.md)

## Android preview

The Android launcher opens `AndroidPreviewApp` in `com.polvpn.app.PreviewActivity`. Its native channel reads Android version, API level and architecture and exports the preview report through Android's local document picker. The merged manifest omits internet access, Android VPN services, the quick tile and widget, and disables app backup. The preview keeps the Go daemon dormant and displays VPN, authentication and quota as unavailable. The Android build checks the manifest in the packaged APK. The upstream Kotlin namespace and JNI names remain aligned for a later authorized integration.

## Retained upstream components

| Component | Role |
| --- | --- |
| `app/lib/main.dart`, `app/lib/ui/` | Flutter shell and screens. `runAndroid` loads settings and starts the controller. |
| `app/lib/core/` | Dart models, controller, and private HTTP client for settings, accounts, status, locations, tests and logs. `AndroidCore` uses a Flutter method channel for platform operations. |
| `app/android/app/src/main/kotlin/com/arman/firefoxvpn/` | `MainActivity` handles VPN consent and method-channel calls. `CoreService` hosts Android's foreground VPN, network callbacks, routes and split-tunnel configuration. A Quick Settings tile and home-screen widget use the same service. |
| `app/android/hev-socks5-tunnel/` | Native packet processing. `Tun2Socks` loads the JNI library, transfers packets to SOCKS5 and closes the TUN descriptor. |
| `core/mobile/` | The gomobile Android bridge starts the Go daemon in the application process. The dashboard uses loopback and a per-run local token. |
| `core/internal/` | Shared provider, account, proxy, routing, resolver and service code. Future desktop releases can reuse it. |

The binary flow is `Android VpnService → TUN → hev-socks5-tunnel → authenticated loopback SOCKS5 → Go proxy → service endpoint`. Use an independent Android application ID and retain the upstream Kotlin namespace for JNI. The default TUN routes cover IPv4 and IPv6 and can restrict VPN traffic to an include or exclude list. Android's package exclusion keeps the app's own sockets off the VPN route. Route and DNS isolation still require physical-device testing. [CoreService](../app/android/app/src/main/kotlin/com/arman/firefoxvpn/CoreService.kt) · [Native bridge](../app/android/app/src/main/kotlin/com/arman/firefoxvpn/Tun2Socks.kt) · [Mobile core](../core/mobile/mobile.go)

## Service and connection state

The upstream data model keeps account state, provider quota, and live connection status separate. Reuse these interfaces for POL's UI. Guardian supplies quota headers. Firefox Remote Settings supplies the endpoint list. The core selects the recommended or a user-chosen location, skips recent endpoint failures when alternatives exist and attempts a bounded reconnect. Android reports underlying network changes to Go and handles service revocation and tunnel cleanup. Raw account errors and verbose logs need sanitization before any POL report or export. [Connection controller](../core/internal/service/connect.go) · [Endpoint selection](../core/internal/proxy/selection.go) · [Status model](../core/internal/proxy/status.go) · [Quota parsing](../core/internal/guardian/usage.go)

The source retains the upstream provider implementation for provenance and future review. Live POL access requires a supported OAuth client, permitted VPN scope and provider approval. A production session needs Android Keystore-backed token storage, backup exclusions, logout and revoked-session handling. Maintain the current Flutter and Go interfaces while integrating any approved flow. [Upstream audit](UPSTREAM_AUDIT.md)

## Build and synchronization

Android links `core.aar` generated from `core/mobile` and builds the packet engine with ndk-build. Flutter drives Gradle and packages the native libraries for supported Android ABIs. Future desktop targets use the Go core as a separate executable. Keep mobile and branding changes outside portable Go packages where the existing interfaces allow it. [Build configuration](../app/android/app/build.gradle.kts) · [Upstream architecture](../core/doc/ARCHITECTURE.md)
