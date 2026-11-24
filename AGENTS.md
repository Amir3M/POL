# POL VPN project instructions

Read `PROJECT_STATUS.md` and `TASKS.md` before changing the project. The active platform is Android. Keep the Go core portable for future Windows and Linux work.

- Preserve user changes and upstream history. Use the `upstream` remote and the baseline recorded in `docs/UPSTREAM_AUDIT.md`.
- Keep the upstream Flutter/Dart shell, Kotlin Android service, Go core and native TUN adapter. Prefer small changes at existing boundaries. Keep branding and UI commits separate from core changes.
- Reproduce the unmodified Android baseline in a detached worktree before changing product behavior or UI. Record the exact commands and outcomes in `docs/TEST_REPORT.md`.
- Require provider authorization for a POL-specific OAuth registration, service scopes and any relay use before enabling live traffic. Run default offline tests without the `live` build tag. Use a system-browser sign-in and approved OAuth contract once available.
- Keep passwords, authentication tokens and signing files out of Git, APK content, reports and logs. Test with an owner-controlled account only after authorization. Review Android backup and local storage before storing any session material.
- Preserve upstream and dependency license notices. Treat source and notice packaging as part of distributing an APK.
- Use persistent signing identities for debug updates and separate production signing. Build and test before publishing. Maintain `PROJECT_STATUS.md`, `TASKS.md` and the test report with verified results.
