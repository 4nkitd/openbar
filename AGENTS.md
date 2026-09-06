# AGENTS.md

## Repo layout

Two surfaces in one repo:

- **The app**: `CodexBarLite`, a native macOS 13+ menu bar agent (SwiftPM executable, AppKit — no SwiftUI) that shows OpenAI Codex CLI usage by reading `~/.codex/auth.json`. Single target in `Sources/CodexBarLite/`; only dependency is Sparkle.
- **The landing page**: `docs/`, a plain static HTML/CSS/JS site (no build step, no framework) deployed via GitHub Pages to getcodexbar.xyz. Read `DESIGN.md` (design system) and `PRODUCT.md` (product/copy truth) before editing it.

## Commands

- `swift build -Xswiftc -warnings-as-errors` — compile the app.
- `bash scripts/check.sh` — offline regression checks and native AppKit screenshots using `swiftc`; works with Command Line Tools without XCTest. Output goes to a temporary directory, or `CHECK_OUTPUT_DIR`.
- `BUILD_ONLY=1 ./scripts/install.sh` — release build + assemble `dist/CodexBarLite.app` (ad-hoc codesign) without touching the system.
- `./scripts/install.sh` — same, then **replaces `/Applications/CodexBarLite.app` and launches it** (kills any running instance). Env overrides: `APP_VERSION`, `BUILD_NUMBER`, `CODESIGN_IDENTITY` (default `-` = ad-hoc).
- `./scripts/release.sh <version> <build-number>` — Sparkle release: builds the update zip and regenerates root `appcast.xml`. Requires the Sparkle EdDSA private key in the login keychain or the appcast step fails.

`install.sh` runs `swift build -c release` itself — no need to build first (README is misleading here). The Info.plist is generated inline by `install.sh`; there is no checked-in plist.

## App notes

- `App.swift` holds the app delegate; `Integrations.swift` owns credentials and HTTP adapters; `QuotaStore.swift` owns per-provider polling, cooldowns, cancellation and the `quotas-v2.json` cache. UI is split across `UsagePopoverViewController.swift`, `SettingsWindowController.swift`, and `Components.swift`.
- Codex usage comes from unofficial `https://chatgpt.com/backend-api/wham/usage`, with `/codex/usage` on HTTP 404. Other provider endpoints are listed in README. Each provider keeps timestamped readings in `~/Library/Application Support/CodexBarLite/quotas-v2.json`; stale data never triggers notifications. Some endpoints can change without notice.
- Sparkle updates and the launch-at-login default are deliberately gated on running from a real `.app` bundle with `SUFeedURL`/`SUPublicEDKey`. Running the bare binary (`swift run`, `.build/...`) skips both — do not remove those guards.
- Debugging the happy path requires a real Codex CLI session (`codex login` → `~/.codex/auth.json`) and hits the live endpoint. UserDefaults domain: `dev.vaibhav.codexbar`.

## Release gotchas

- Root `appcast.xml` is the live Sparkle feed (`SUFeedURL` points at raw.githubusercontent.com/.../main/appcast.xml) — committed on purpose; never delete or gitignore it.
- After a release, manually bump the hardcoded download link in `README.md` (`.../download/vX.Y.Z/...`).
- The `-arm64.dmg` attached to GitHub releases is produced by no script in this repo; `release.sh` only makes the Sparkle zip.
- `dist/`, `.build/`, `.impeccable/` are gitignored build output.

## Landing page rules (docs/)

- Static HTML/CSS/JS only — no build step, no framework (per `.impeccable/surfaces/docs-index-html.md`). The one allowed JS is small vanilla animation respecting `prefers-reduced-motion`.
- The published site still describes v0.2.5, not the unreleased multi-provider build. Before releasing that build, update the site's access claims and screenshots: integrations now use Keychain and optional tokens. Keep the no-browser-cookies/no-third-party-backend claims precise; never fabricate testimonials, press, or stats or imply provider affiliation.
- The page is maintained with the `impeccable` skill vendored at `docs/.agents/skills/impeccable`; surface state lives in `.impeccable/surfaces/`.
