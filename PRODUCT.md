# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary: an individual developer who already uses the Codex CLI (`codex login`) on their own Mac. They land on this page from GitHub or word of mouth, wanting at-a-glance Codex usage in their menu bar without granting the app any new access to their machine.

## Product Purpose

CodexBar Lite is a tiny native macOS menu bar app that shows Codex usage (primary/secondary usage, reset times) by reading the local session `codex login` already created, and notifies at 80%, 90%, exhaustion, and credit reset. It exists so developers can see their usage without a dashboard, browser extension, or third-party account.

## Positioning

Usage trackers typically ask for Chrome access, browser cookies, macOS Keychain, Accessibility, Screen Recording, Full Disk Access, or an API key just to show a number. CodexBar Lite needs none of that — it reads the existing `~/.codex/auth.json` session and talks directly to `chatgpt.com`. The claim a competitor cannot truthfully copy without also giving up their broader access model: "your Codex login is enough."

## Operating Context

- Requires an Apple Silicon Mac, macOS 13 Ventura or newer, with the Codex CLI installed and `codex login` already run.
- Install: download from GitHub Releases, move `CodexBarLite.app` to `/Applications`, open it.
- If no Codex session exists yet, the app launches `codex login` in Terminal and watches for completion.
- Updates ship over the air via Sparkle (`Codex → Check for Updates…`).
- Build from source: `swift build` + `./scripts/install.sh`; signed releases via `./scripts/release.sh <version> <build-number>`.
- Uninstall: quit and trash the app; optional cleanup removes `~/Library/Application Support/CodexBarLite` and the `dev.vaibhav.codexbar` defaults domain.

## Capabilities and Constraints

- Reads only `~/.codex/auth.json`; makes the minimum request needed to show usage directly to `chatgpt.com`.
- No Chrome/browser-profile access, no cookies, no macOS Keychain, no Accessibility, no Screen Recording, no Full Disk Access, no API key, no third-party backend or account.
- No telemetry or analytics; stores only preferences and a local usage cache.
- Settings: tabbed General, Authentication, Notifications, and About panes; refresh every 1/5/15/30 minutes, Launch at Login, percentage used vs. remaining, automatic update checks, and notification controls.
- Deliberately excludes dashboards, browser extensions, graphs, themes, and account switching — scope stays "menu bar usage, nothing more."
- Independent project: not affiliated with, endorsed by, or sponsored by OpenAI.

## Brand Commitments

- Name: CodexBar Lite. Logo asset: `assets/codexbar-lite-blue-dot.png` (also copied to `docs/assets/logo.png`) — a near-black rounded-square app icon with one solid blue circle (`#1475FC`), the pinned primary brand color.
- Existing screenshots: `assets/screenshots/hero-menu-bar.png` (blue status ring with a white percentage label), `assets/screenshots/dropdown.png` (card-based usage popover), `assets/screenshots/preferences.png` (tabbed Settings window). Also `assets/banner.png`, a marketing render with the tagline "Your Codex usage. Right in your menu bar." — reusable copy.
- Voice, as established in the README: direct, unhedged claims about what the app does *not* access; matter-of-fact rather than marketing-heavy.
- **Standing landing-page direction (pinned 2026-07-23):** dark, near-black ground matching the logo's icon background, with the logo's blue (`#1475FC`) carried at Committed intensity (30-60% of the surface, not a sparing accent). Craft bar is [kraten.github.io/chimlo](https://kraten.github.io/chimlo) — a dark, confident developer-tool launch page (bold display headline, interactive product hero, feature grid, trust/privacy checklist section, FAQ accordion, closing CTA) — adapted to CodexBar Lite's own content and real screenshots, not copied verbatim. Product UI uses the ring-based menu icon, card-based popover, and tabbed Settings window from the app.

## Evidence on Hand

- Product facts, feature list, and install/uninstall steps: `README.md`.
- Screenshots listed above under Brand Commitments.
- No testimonials, press mentions, download counts, or other social proof exist yet — future work must not fabricate any.

## Product Principles

1. Access claims are the product's core credibility; every design and copy decision must keep "no Keychain, no cookies, no API key, no third-party account" verifiable and prominent, never softened into vague "privacy-friendly" language.
2. Stay as small and unbloated in presentation as the app itself is in scope — no manufactured feature surface, dashboards, or busywork to look more substantial.
3. Speak to a developer audience that can verify claims by reading code or `auth.json` handling themselves; prefer precise, checkable statements over marketing abstraction.
4. Never imply OpenAI affiliation, endorsement, or sponsorship.

## Accessibility & Inclusion

No product-specific accessibility requirement has been established beyond standard web accessibility practice.
