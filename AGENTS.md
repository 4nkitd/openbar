# AGENTS.md

## Repo layout

Two surfaces in one repo:

- **The app**: `CodexBarLite`, a native macOS 13+ menu bar agent (SwiftPM executable, AppKit — no SwiftUI) that shows OpenAI Codex CLI usage by reading `~/.codex/auth.json`. Single target in `Sources/CodexBarLite/`; only dependency is Sparkle.
- **The landing page**: `docs/`, a plain static HTML/CSS/JS site (no build step, no framework) deployed via GitHub Pages to getcodexbar.xyz. Read `DESIGN.md` (design system) and `PRODUCT.md` (product/copy truth) before editing it.

## Commands

- `swift build` — the only verification that exists. There are no tests and no test target.
- `BUILD_ONLY=1 ./scripts/install.sh` — release build + assemble `dist/CodexBarLite.app` (ad-hoc codesign) without touching the system.
- `./scripts/install.sh` — same, then **replaces `/Applications/CodexBarLite.app` and launches it** (kills any running instance). Env overrides: `APP_VERSION`, `BUILD_NUMBER`, `CODESIGN_IDENTITY` (default `-` = ad-hoc).
- `./scripts/release.sh <version> <build-number>` — Sparkle release: builds the update zip and regenerates root `appcast.xml`. Requires the Sparkle EdDSA private key in the login keychain or the appcast step fails.

`install.sh` runs `swift build -c release` itself — no need to build first (README is misleading here). The Info.plist is generated inline by `install.sh`; there is no checked-in plist.

## App notes

- `main.swift` holds the app delegate, auth reading, networking, action menu, and cache. UI is split across `UsagePopoverViewController.swift`, `SettingsWindowController.swift`, and `Components.swift`; supporting helpers include `Settings.swift`, `NotificationManager.swift`, and `Branding.swift`.
- Usage comes from the unofficial endpoint `https://chatgpt.com/backend-api/codex/usage` while impersonating the Codex CLI (`User-Agent: codex-cli/0.11.0`, `originator: codex_cli_rs`, `chatgpt-account-id` header). It can break when OpenAI changes it. A Cloudflare HTML challenge falls back to the cache at `~/Library/Application Support/CodexBarLite/usage.json`.
- Sparkle updates and the launch-at-login default are deliberately gated on running from a real `.app` bundle with `SUFeedURL`/`SUPublicEDKey`. Running the bare binary (`swift run`, `.build/...`) skips both — do not remove those guards.
- Debugging the happy path requires a real Codex CLI session (`codex login` → `~/.codex/auth.json`) and hits the live endpoint. UserDefaults domain: `dev.vaibhav.codexbar`.

## Release gotchas

- Root `appcast.xml` is the live Sparkle feed (`SUFeedURL` points at raw.githubusercontent.com/.../main/appcast.xml) — committed on purpose; never delete or gitignore it.
- After a release, manually bump the hardcoded download link in `README.md` (`.../download/vX.Y.Z/...`).
- The `-arm64.dmg` attached to GitHub releases is produced by no script in this repo; `release.sh` only makes the Sparkle zip.
- `dist/`, `.build/`, `.impeccable/` are gitignored build output.

## Landing page rules (docs/)

- Static HTML/CSS/JS only — no build step, no framework (per `.impeccable/surfaces/docs-index-html.md`). The one allowed JS is small vanilla animation respecting `prefers-reduced-motion`.
- Copy rules from `PRODUCT.md`: the "no Keychain / no cookies / no API key / no third-party account" claims are the product's core credibility — keep them precise and verifiable; never fabricate testimonials, press, or stats; never imply OpenAI affiliation.
- The page is maintained with the `impeccable` skill vendored at `docs/.agents/skills/impeccable`; surface state lives in `.impeccable/surfaces/`.
