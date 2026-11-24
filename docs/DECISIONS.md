# Decisions

| Decision | Rationale |
| --- | --- |
| Pin Arman v1.0.19 at `492dd7f389c539790cde3d07167535d28788a0d0` | The upstream latest release and main branch resolve to this commit. A detached worktree isolates baseline verification. |
| Preserve both Git histories | The import merges the existing POL initial commit with the upstream commit. The first parent stays on the POL branch, and the second parent stays on the upstream history. Upstream publishing workflows remain available in that history. |
| Retain Flutter, Kotlin, Go and the C TUN adapter | These are the upstream components. The Go package paths and Android Kotlin namespace can stay stable while the APK obtains an independent application ID. JNI depends on the namespace. |
| Reserve `com.polvpn.app` and `com.polvpn.app.debug` for POL builds | Both meet Android's package syntax requirements. Exact public searches found no collision. Play Console reservation is unverified. |
| Gate live Mozilla functionality on provider authorization | The upstream OAuth identity belongs to Firefox Desktop. The free built-in VPN is scoped to browser traffic, and Mozilla has publicly investigated unauthorized third-party use. Production requires POL-specific client authorization, a registered redirect URI, approved scopes and the service contract. |
| Treat the attached image as the POL logo reference | Picture2.png is a visual asset. Generate replaceable Android launcher and adaptive assets during rebranding. |

## Provider sources

- Mozilla documents first-party OAuth IDs and the production Mozilla Accounts integration process. [OAuth clients](https://mozilla.github.io/ecosystem-platform/fxa-sitemap/flow-oauth-relying-party) · [Integration tutorial](https://mozilla.github.io/ecosystem-platform/relying-parties/tutorials/integration-with-fxa)
- Mozilla documents the Firefox built-in VPN's browser coverage and responded publicly to unauthorized third-party use. [Feature scope](https://support.mozilla.org/en-US/kb/built-in-vpn) · [Mozilla community response](https://connect.mozilla.org/t5/discussions/mozilla-s-double-standards-privacy-for-some-exclusion-for/m-p/146684)
- Mozilla announced a temporary uncapped data period through January 31, 2027 for eligible Firefox users. POL's quota display will need to use its authorized service responses. [Quota announcement](https://blog.mozilla.org/en/firefox/built-in-vpn-unlimited-data/)

## Upstream synchronization

On a fresh clone, add the upstream remote if needed and fetch upstream tags. Use a dedicated integration branch to inspect the changes since the pinned commit and merge the chosen upstream commit after review. Check Android build pins, licensing, service configuration and retained GitHub workflows. Review POL branding and Android gate behavior after the merge, rerun build verification and update the baseline record with the new commit.

```sh
git remote add upstream https://github.com/armanlife/arman-vpn-client.git
git fetch upstream --tags
git log 492dd7f389c539790cde3d07167535d28788a0d0..upstream/main
```
