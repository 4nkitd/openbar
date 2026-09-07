# AGENTS.md

## Repo layout

Two surfaces in one repo:

- **The app**: `OpenBar`, a native macOS 13+ menu-bar app (SwiftPM executable, AppKit, no SwiftUI). Single target in `Sources/OpenBar/`; only dependency is Sparkle. Supports multiple configured accounts for each integration.
- **The landing page**: `docs/`, a plain static HTML/CSS/JS site (no build step, no framework) deployed via GitHub Pages to getcodexbar.xyz. Read `DESIGN.md` (design system) and `PRODUCT.md` (product/copy truth) before editing it.

## Commands

- `swift build -Xswiftc -warnings-as-errors` — compile the app.
- `bash scripts/check.sh` — offline regression checks and native AppKit screenshots using `swiftc`; works with Command Line Tools without XCTest. Output goes to a temporary directory, or `CHECK_OUTPUT_DIR`.
- `BUILD_ONLY=1 ./scripts/install.sh` — release build + assemble `dist/OpenBar.app` (ad-hoc codesign) without installing.
- `./scripts/install.sh` — same, then **replaces `/Applications/OpenBar.app` and launches it**. Env overrides: `APP_VERSION`, `BUILD_NUMBER`, `CODESIGN_IDENTITY` (default `-` = ad-hoc).
- `./scripts/release.sh <version> <build-number>` — build a platform-specific ZIP and print SHA-256. Generates `appcast.xml` only when explicit Sparkle feed/public-key configuration is present; that optional step needs the matching private signing key in Keychain.

`install.sh` runs `swift build -c release` itself — no need to build first (README is misleading here). The Info.plist is generated inline by `install.sh`; there is no checked-in plist.

## App notes

- `App.swift` holds the app delegate; `Accounts.swift` models configured accounts; `Integrations.swift` owns credentials and HTTP adapters; `QuotaStore.swift` owns per-account polling, cooldowns, cancellation and the `accounts-v1.json` cache. `AccountsPreferencesView.swift` manages accounts within Settings.
- Codex usage comes from unofficial `https://chatgpt.com/backend-api/wham/usage`, with `/codex/usage` on HTTP 404. Each account keeps timestamped readings in `~/Library/Application Support/OpenBar/accounts-v1.json`; stale data never triggers notifications. Google OAuth clients are configured locally in Keychain or environment, never embedded in source.
- Sparkle updates and the launch-at-login default are deliberately gated on running from a real `.app` bundle with `SUFeedURL`/`SUPublicEDKey`. Running the bare binary (`swift run`, `.build/...`) skips both — do not remove those guards.
- UserDefaults domain: `in.4nkitd.openbar`; known preferences migrate once from `dev.vaibhav.codexbar`. The old Keychain service is retained to preserve saved account tokens. Explicit credential-file accounts must never fall back to another sign-in.

## Release gotchas

- Root `appcast.xml` is committed on purpose; never delete or gitignore it. It is now an empty OpenBar feed, not the old project's live releases. Updates are disabled unless `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_KEY` are explicitly supplied; never restore the upstream feed or signing key.
- After a release, manually bump the hardcoded download link in `README.md` (`.../download/vX.Y.Z/...`).
- The `-arm64.dmg` attached to GitHub releases is produced by no script in this repo; `release.sh` only makes the Sparkle zip.
- `dist/`, `.build/`, `.impeccable/` are gitignored build output.

## Landing page rules (docs/)

- Static HTML/CSS/JS only — no build step, no framework (per `.impeccable/surfaces/docs-index-html.md`). The one allowed JS is small vanilla animation respecting `prefers-reduced-motion`.
- The published site still describes v0.2.5, not the unreleased multi-provider build. Before releasing that build, update the site's access claims and screenshots: integrations now use Keychain and optional tokens. Keep the no-browser-cookies/no-third-party-backend claims precise; never fabricate testimonials, press, or stats or imply provider affiliation.
- The page is maintained with the `impeccable` skill vendored at `docs/.agents/skills/impeccable`; surface state lives in `.impeccable/surfaces/`.
