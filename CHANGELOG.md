# Changelog

## 0.1.3

- Brand-colored progress bars for each integration app (Codex Teal, Claude Coral, OpenCode Purple, Copilot Blue, Antigravity Blue).
- Fully rebranded landing page and docs website for OpenBar (`https://4nkitd.github.io/openbar/`).
- Removed all Umami analytics tracking scripts and attributes from the site.
- Refreshed native AppKit UI screenshots across README and documentation.

## 0.1.0

First OpenBar release, continuing the menu-bar quota work from Headroom.

- Native AppKit menu-bar app for macOS 13+ on Apple Silicon.
- Codex, Claude Code, OpenCode Go, GitHub Copilot and Antigravity integrations using direct HTTP APIs.
- Multiple named accounts, separate credentials and independent refresh, retry and cache state.
- Compact per-account progress bars, expandable quota windows and reset timers.
- Local Keychain storage for entered tokens and optional Google OAuth client configuration. No embedded client secrets.
- Non-interactive background Keychain reads, so protected sign-ins do not stall refreshes.
- OpenBar app identity, About pane, GitHub links and preference compatibility with earlier development builds.
- Offline regression checks for account routing, cancellation, cache migration and native UI states.

### Installation and limitations

- Install with `brew install --cask 4nkitd/tap/openbar`, or download the ARM64 ZIP from GitHub Releases.
- The app is ad-hoc signed, not notarized. macOS may require approval in Privacy & Security.
- Google OAuth refresh requires locally configured client credentials. Protected legacy Keychain sign-ins may require explicit authorization or an existing credential file.
- GitHub's internal quota API requires a compatible Copilot token; not every PAT works.
- Sparkle automatic updates are not configured. Use Homebrew to upgrade.
- OpenBar focuses on menu-bar quotas; it does not include Headroom's widgets or notch HUD.
