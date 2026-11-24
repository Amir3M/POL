# Android device test checklist

Record the APK SHA-256 and signer fingerprint, package ID, app version, Android version, device architecture, date, and results. Keep account identifiers, tokens, public IP values, and browsing information out of shared reports. Run the live checks after POL has an approved provider configuration.

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
