# Android device test checklist

Record the APK SHA-256 and signer fingerprint, package ID, app version, Android version, device architecture, date, and results. Keep account identifiers, tokens, public IP values, and browsing information out of shared reports.

## Controlled tunnel test

Use the **Tunnel Test** prerelease, Android 7.0 or later and a browser or HTTP client installed as a separate Android app.

1. Stop any VPN connection and close Arman. Install the signed tunnel-test APK over the existing 0.1.1 preview without uninstalling. Confirm the app shows **Tunnel Test** and build number 3 or higher.
2. With POL disconnected, open `http://192.0.2.1:8080/` from the other app. It should fail to show the test response. Use the exact HTTP URL and a client that accepts HTTP to a numeric address. Disable an HTTPS-only setting for this check if needed.
3. In POL, create the synthetic session. Force-stop POL in Android's app settings and reopen it. Verify that the session is restored.
4. Tap **Connect**, approve Android's VPN dialog, and check Diagnostics for TUN establishment, proxy authorization and connection. Check the quota returned by the fixture and use **Renew test session** to exercise simulated token refresh. In the other app, open the same test URL in a new tab to fetch a fresh response. Verify that it shows the fixture response. Exercise the upload and download controls on that page and check that Diagnostics records traffic.
5. Disconnect in POL. Open a fresh tab in the second app and verify it cannot fetch a new test response. Connect and approve again if prompted. Record any stage that fails. Check diagnostic text before sharing it.
6. Sign out, close and reopen POL, and confirm the synthetic session is gone and connecting requires a new one. To test persistence across a future signed update, first create a session on the existing tunnel-test build, install a higher build number with the same signer over it, then reopen and verify that the session is restored.

The tunnel owns only the test IPv4 route `192.0.2.1/32`. The destination and response are generated on the device. Mozilla sign-in, Guardian, Internet traffic through the VPN and live quota are covered by separate tests after provider authorization.

## Live VPN testing

Run the following checks after POL has an approved provider configuration.

## Install, account and updates

- Install the debug APK and confirm the display name, icon, package ID and version. Open it in airplane mode and verify the offline status, About and Diagnostics screens. The preview uses Android 7.0 or later.
- Sign in interactively with an authorized test account. Check cancellation, account switching or removal, token refresh, expired or revoked sessions, sign-out, and manual reset.
- Close and reopen, reboot, and update to a higher version signed with the same key. Verify that the session persists where expected, reset remains effective, and debug and production data are isolated.
- Refresh quota and capture the status only. Exercise limited, unlimited, unavailable, failed-refresh and exhausted responses with approved fixtures or a provider test account.

## Traffic and resilience

- Establish an offline or disconnected baseline for the device's default route and prepare controlled HTTPS, DNS, and upload/download endpoints.
- Connect and verify TLS-backed HTTPS fetch, hostname resolution, a public IP change matching the approved exit, and successful data transfers in both directions. Compare session traffic counters with the transfers. Repeat for the automatic location and an approved manual location.
- Disconnect and reconnect repeatedly. Cover endpoint failure, airplane mode, Wi-Fi to mobile data and back, background use, screen-off use, reboot, and a long-running transfer. Check notification and reconnect state and confirm cleanup on disconnect and permission revocation.
- Test included and excluded apps and destinations. Look for DNS and IPv6 leaks while connected and during transitions. Verify Android Always-on and lockdown behavior separately. Record expected direct traffic for explicitly excluded apps.
- Observe memory, CPU and battery for a representative long connection and idle session. Record Android's measurement interval and compare against an idle baseline.

## Diagnostics

- Copy a report, then export it through the system file picker. Confirm the contents match and include the version, build ID, Android version, SDK and architecture. Cancel a second export and confirm the app resumes normally.
- Check the preview's VPN, authentication and quota states are unavailable. Inspect the report for passwords, tokens, session secrets, browsing or DNS history, precise network addresses and personal information.
- Once live diagnostics are enabled, test connection and reconnection entries, error sanitization and log clearing.
