# OpenBar

Native macOS menu-bar monitoring for your AI coding subscriptions. See each account's quota and reset times without keeping provider dashboards open.

[Source](https://github.com/4nkitd/openbar) · [Issues](https://github.com/4nkitd/openbar/issues)

OpenBar continues the menu-bar quota work from [Headroom](https://github.com/4nkitd/headroom). The inherited `docs/` website still describes the original CodexBar Lite release and is not the OpenBar website.

## Install

Requires an Apple Silicon Mac running macOS 13 Ventura or later.

```bash
brew install --cask 4nkitd/tap/openbar
open -a OpenBar
```

Or download [OpenBar v0.1.0](https://github.com/4nkitd/openbar/releases/download/v0.1.0/OpenBar-0.1.0-macos-arm64.zip), unzip it, and move **OpenBar.app** into **Applications**.

This release is ad-hoc signed and is not notarized. If Gatekeeper blocks the app, review the download source and allow it under **System Settings → Privacy & Security → Open Anyway**. Homebrew updates are available through `brew upgrade --cask 4nkitd/tap/openbar`.

### Moving from Headroom

Quit Headroom and disable its launch-at-login setting before switching. If you use its CLI, `headroom disable` turns off that startup entry. OpenBar can reuse supported provider sign-ins, but Headroom-specific preferences, extra account labels, widgets and the notch HUD are not migrated. Configure your accounts in **OpenBar → Integrations**.

## What it shows

- OpenAI Codex, Claude Code, OpenCode Go, GitHub Copilot and Google Antigravity.
- Multiple named accounts per integration, with independent credentials, refresh state, cached readings and enable/disable switches.
- A compact progress bar for each account's most-constrained quota. Expand a provider to see every window and reset time.
- A menu-bar summary of the most-constrained enabled account, with the account named in its tooltip.
- Used or remaining percentages, light/dark appearance, scrollable expanded details and keyboard controls.
- Notifications at 80%, 90%, exhaustion and quota reset. Stale cache values do not trigger alerts.

## Add accounts

Open **Integrations…** from the popover and choose a provider.

| Provider | Account setup | Usage source |
| --- | --- | --- |
| Codex | Use the current CLI login or choose a separate account's `auth.json` file | OpenAI Codex usage API |
| Claude Code | Use the current Claude/OpenCode login or choose a separate Claude credentials JSON or OpenCode auth JSON | Anthropic OAuth usage API |
| OpenCode Go | Use OpenCode's current key, or add separately named API keys | OpenCode Go usage API |
| GitHub Copilot | Add a separate compatible token for each account | GitHub's internal Copilot quota API |
| Antigravity | Import the current local sign-ins or choose a separate Google token / Antigravity account JSON file | Google Code Assist quota APIs |

Name additional accounts, such as **Personal** and **Work**, then enter the token or select the existing credential file. Accounts appear under their provider in the popover. **Edit** changes the label or credentials. **Remove** removes the OpenBar configuration and its saved token, not the original sign-in file. Disabling one account does not disable its siblings.

OpenBar does not implement new OAuth sign-in flows. Extra OAuth accounts must already be signed in through their provider tools. Select the file for the intended account; do not use one shared file for different identities. The **Use current login** entry follows the active sign-in. If an imported file contains several Google accounts, that source shows all of them; use separate credential files when you need independent controls for each one.

GitHub's unofficial quota endpoint does not accept every personal access token. The account is marked **Verified** only after a successful quota response. Saving a token alone is not proof of access.

### Antigravity OAuth setup

Google OAuth client secrets are **not embedded in the app or repository**. OpenBar can use a valid access token from an existing login. Refreshing an expired token needs the OAuth client belonging to that login.

Choose **Integrations → Antigravity → Configure OAuth…** and save the appropriate Antigravity or Gemini client ID and client secret. These values stay in the macOS Keychain. They are not provider account tokens and cannot replace an account's existing sign-in.

Alternatively, supply `ANTIGRAVITY_OAUTH_CLIENT_ID` / `ANTIGRAVITY_OAUTH_CLIENT_SECRET`, or `GEMINI_OAUTH_CLIENT_ID` / `GEMINI_OAUTH_CLIENT_SECRET`, in the app's process environment. Finder-launched apps do not inherit terminal environment variables. Never commit these values.

For one-time local setup from an already configured environment, launch `dist/OpenBar.app/Contents/MacOS/OpenBar --import-google-oauth-clients`. OpenBar itself saves the complete client pairs to Keychain, so no external helper owns those entries. The command logs only the number of imported clients. Subsequent launches can use Keychain without those environment variables.

## Privacy and storage

All quota collection uses in-process HTTP requests to the issuing provider. There is no browser scraping, browser-cookie access, local usage estimation, telemetry or OpenBar backend. Claude polling calls the read-only OAuth usage endpoint; it does not submit model inference requests.

- Account names, file paths, enable switches and preferences use the `in.4nkitd.openbar` UserDefaults domain.
- Account API tokens and refreshed Claude credential caches use Keychain. The internal service name `dev.vaibhav.codexbar.integrations` is deliberately retained for compatibility with the earlier development build.
- Google OAuth client configuration uses the separate `in.4nkitd.openbar.oauth` Keychain service.
- Quota snapshots live in `~/Library/Application Support/OpenBar/accounts-v1.json`, written atomically with mode `0600` and a separate success timestamp per configured account.
- Existing preferences and `CodexBarLite/quotas-v2.json` readings are copied on first launch without deleting the original data. Launch-at-login registration is tied to the new app bundle; check the switch after installing OpenBar.
- Codex token refresh updates only the selected account's auth file and preserves unrelated JSON fields. Claude refresh caches are scoped to their configured account and source sign-in.

Background Keychain reads do not show authorization dialogs or wait for permission. If an older sign-in is protected by another app's access controls, use that account's existing credential file or explicitly allow OpenBar in Keychain Access. A readable account can continue refreshing while another sign-in is inaccessible.

Manual refreshes observe a minimum interval of one minute per account, or five minutes for Claude. Failures back off up to 30 minutes, and a longer server `Retry-After` is respected. Opening the popover or changing display preferences does not trigger requests.

## Build and run

Requires macOS 13 or later and Swift 5.10 or later. The app is AppKit-based; Sparkle is its only SwiftPM dependency.

```bash
git clone https://github.com/4nkitd/openbar.git
cd openbar
swift build -Xswiftc -warnings-as-errors
BUILD_ONLY=1 ./scripts/install.sh
open dist/OpenBar.app
```

This creates `dist/OpenBar.app` without replacing anything in `/Applications`. To install there, run `./scripts/install.sh` without `BUILD_ONLY=1`. It replaces `/Applications/OpenBar.app`, not the old CodexBar Lite app.

Enable launch at login in General settings, or launch the installed app once with `--enable-launch-at-login`. If macOS requires approval, allow OpenBar under Login Items. `--diagnostics` prints account refresh status and Keychain error codes to stderr without credential values.

The blue-dot icon is retained from the original project. Build output and local credentials are not committed.

### Verification

```bash
bash scripts/check.sh
```

The regression checks compile the actual sources with `swiftc` and work with Command Line Tools alone, without XCTest. They use fixtures and an intercepted HTTP transport, not live credentials. Checks cover response parsing, account-specific credential routing, independent failures and retry delays, cancellation/removal, migration, UI view reuse, expandable scrolling, and light/dark/error/empty states. Test screenshots and caches go to a temporary directory, or `CHECK_OUTPUT_DIR`.

### Updates and releases

Automatic updates are disabled by default. OpenBar does not use CodexBar Lite's update feed or signing key. The checked-in `appcast.xml` is an empty OpenBar feed until a release is created.

`scripts/release.sh <version> <build-number>` creates a platform-specific release ZIP and prints its SHA-256. To also generate a Sparkle feed, set an accessible HTTPS `SPARKLE_FEED_URL` and matching `SPARKLE_PUBLIC_KEY`, with the matching signing key in Keychain. No release credentials are bundled.

## Credits

OpenBar is maintained by [4nkitd](https://github.com/4nkitd), based on [CodexBar Lite](https://github.com/wei-b0/codexbar-lite). HTTP integration references came from [Headroom](https://github.com/4nkitd/headroom) and [OpenCode Bar](https://github.com/opgginc/opencode-bar). See [third-party notices](THIRD_PARTY_NOTICES.md).

OpenBar is independent of OpenAI, Anthropic, GitHub, Google and OpenCode. Provider names and marks identify integrations, not affiliation or endorsement.
