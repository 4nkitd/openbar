# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary: an individual developer who uses one or more AI coding subscriptions on their Mac and wants every active quota visible in one compact menu-bar popover.

## Product Purpose

The native fork is now named **OpenBar** and maintained at `https://github.com/4nkitd/openbar`. It supports multiple named accounts per integration. The website's historical CodexBar Lite branding is intentionally unchanged; README documents current native behavior.

The multi-provider changes below are unreleased source behavior. The published landing page and v0.2.5 release remain Codex-only until a coordinated release updates them.

CodexBar Lite is a native macOS menu bar app that shows quota windows and reset times for OpenAI Codex, Claude Code, OpenCode Go, GitHub Copilot, and Gemini Antigravity. Each enabled integration gets its own linear progress bars. It notifies at 80%, 90%, exhaustion, and quota reset.

## Positioning

Usage comes from provider HTTP APIs, never browser scraping or provider CLI execution. Existing OAuth stores are reused where available; manually configured GitHub and OpenCode Go tokens are kept in the macOS Keychain. There is no CodexBar account or backend.

## Operating Context

- Requires an Apple Silicon Mac, macOS 13 Ventura or newer, and at least one supported provider account.
- Install: download from GitHub Releases, move `CodexBarLite.app` to `/Applications`, open it.
- Codex sign-in is an explicit action in Settings; it opens `codex login` in Terminal and watches for completion for up to five minutes.
- Updates ship over the air via Sparkle (`Codex → Check for Updates…`).
- Build from source: `swift build` + `./scripts/install.sh`; signed releases via `./scripts/release.sh <version> <build-number>`.
- Uninstall: quit and trash the app; optional cleanup removes `~/Library/Application Support/CodexBarLite` and the `dev.vaibhav.codexbar` defaults domain.

## Capabilities and Constraints

- Reads supported providers' existing local OAuth stores and makes direct HTTPS requests to first-party usage endpoints.
- No Chrome/browser-profile access, cookies, Accessibility, Screen Recording, Full Disk Access, provider CLI usage collection, third-party backend, or CodexBar account.
- GitHub and OpenCode Go tokens entered in Settings are stored in the macOS Keychain.
- Google OAuth client secrets are not bundled. Antigravity can use an existing access token; token refresh requires matching OAuth client credentials saved locally in Keychain or supplied at runtime.
- No telemetry or analytics. Stores preferences, timestamped quota caches and explicitly saved credentials in Keychain.
- Settings: tabbed General, Integrations, Notifications, and About panes; provider toggles, secure token fields, refresh every 1/5/15/30 minutes, Launch at Login, percentage used vs. remaining, automatic update checks, and notification controls.
- Deliberately excludes dashboards, browser extensions, graphs, and themes — scope stays "menu bar quotas, nothing more."
- Independent project: not affiliated with, endorsed by, or sponsored by any supported provider.

## Brand Commitments

- Name: CodexBar Lite. Logo asset: `assets/codexbar-lite-blue-dot.png` (also copied to `docs/assets/logo.png`) — a near-black rounded-square app icon with one solid blue circle (`#1475FC`), the pinned primary brand color.
- Existing screenshots predate the multi-provider UI and must be refreshed before release. The small blue menu-bar summary ring remains; the popover now uses one linear quota card per enabled integration.
- Voice, as established in the README: direct, unhedged claims about what the app does *not* access; matter-of-fact rather than marketing-heavy.
- **Standing landing-page direction (pinned 2026-07-23):** dark, near-black ground matching the logo's icon background, with the logo's blue (`#1475FC`) carried at Committed intensity (30-60% of the surface, not a sparing accent). Craft bar is [kraten.github.io/chimlo](https://kraten.github.io/chimlo) — a dark, confident developer-tool launch page (bold display headline, interactive product hero, feature grid, trust/privacy checklist section, FAQ accordion, closing CTA) — adapted to CodexBar Lite's own content and real screenshots, not copied verbatim. Product UI uses the ring-based menu icon, card-based popover, and tabbed Settings window from the app.

## Evidence on Hand

- Product facts, feature list, and install/uninstall steps: `README.md`.
- Screenshots listed above under Brand Commitments.
- No testimonials, press mentions, download counts, or other social proof exist yet — future work must not fabricate any.

## Product Principles

1. Access claims are the product's core credibility: no browser cookies, no dashboard scraping, no provider CLI usage collection, no third-party backend, and credentials sent only to their issuing provider.
2. Stay as small and unbloated in presentation as the app itself is in scope — no manufactured feature surface, dashboards, or busywork to look more substantial.
3. Speak to a developer audience that can verify claims by reading code or `auth.json` handling themselves; prefer precise, checkable statements over marketing abstraction.
4. Never imply provider affiliation, endorsement, or sponsorship.

## Accessibility & Inclusion

No product-specific accessibility requirement has been established beyond standard web accessibility practice.
