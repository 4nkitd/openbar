---
name: CodexBar Lite
description: Native Codex usage in your macOS menu bar — a dark, confident developer-tool launch page built on the logo's blue.
colors:
  bg: "#121212"
  bg-raised: "#1b1b1d"
  bg-inset: "#0c0c0d"
  bg-menubar: "#060606"
  border: "#2a2a2d"
  text: "#f3f3f1"
  text-dim: "#9c9c98"
  text-faint: "#828280"
  on-accent: "#ffffff"
  hairline-highlight: "rgba(255, 255, 255, 0.08)"
  accent: "#1475fc"
  accent-hover: "#3b8bff"
  accent-dim: "#0f5cd1"
  accent-tint: "rgba(20, 117, 252, 0.14)"
  chrome-red: "#ff5f57"
  chrome-yellow: "#febc2e"
  chrome-green: "#28c840"
typography:
  display:
    fontFamily: "'Bricolage Grotesque', 'SF Pro Display', system-ui, sans-serif"
    fontSize: "clamp(2.5rem, 6vw, 4.25rem)"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "'Bricolage Grotesque', 'SF Pro Display', system-ui, sans-serif"
    fontSize: "clamp(1.75rem, 3.5vw, 2.5rem)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  body:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
  label:
    fontFamily: "'SF Mono', ui-monospace, Menlo, monospace"
    fontSize: "0.8125rem"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "0.06em"
  lede:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
  card-title:
    fontFamily: "'Bricolage Grotesque', 'SF Pro Display', system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.01em"
  ui-small:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  ui-small-tight:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: "0.9688rem"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "normal"
  ui-caption:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "normal"
  micro:
    fontFamily: "'SF Mono', ui-monospace, Menlo, monospace"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "0.05em"
  nano:
    fontFamily: "'SF Mono', ui-monospace, Menlo, monospace"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.04em"
  glyph:
    fontFamily: "'Bricolage Grotesque', 'SF Pro Display', system-ui, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "normal"
rounded:
  hairline: "1px"
  glyph: "2px"
  checkbox: "4px"
  xs: "6px"
  sm: "8px"
  md: "14px"
  lg: "20px"
  full: "999px"
spacing:
  xs: "8px"
  sm: "16px"
  md: "24px"
  lg: "48px"
  xl: "96px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#ffffff"
    rounded: "{rounded.full}"
    padding: "14px 28px"
  button-primary-hover:
    backgroundColor: "{colors.accent-hover}"
    textColor: "#ffffff"
    rounded: "{rounded.full}"
    padding: "14px 28px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    rounded: "{rounded.full}"
    padding: "14px 28px"
---

# Design System: CodexBar Lite

## Overview

**Creative North Star: "The Blue Dot, at Committed Scale"**

The landing page is built from the logo outward: a near-black ground identical in character to the icon's own background, with the icon's single blue circle expanded from a 1024×1024 dot into the surface's real structural color — button fills, active states, badges, headline emphasis, checkmarks. The craft bar is a named reference the user pinned, [kraten.github.io/chimlo](https://kraten.github.io/chimlo): a dark, confident developer-tool launch page with a bold display headline, an interactive product hero, a feature grid, a trust/privacy section, an FAQ accordion, and a closing CTA. This system executes that structure at full fidelity, populated with CodexBar Lite's own product truth and its own screenshots — never Chimlo's copy, iconography, or exact green accent.

Where the page touches the product's actual UI (the ring status icon, multi-provider usage popover, and tabbed Settings window), it stays native: real macOS chrome, compact provider cards, linear quota bars, continuous corner radii, and SF system type rather than an illustrated interpretation.

**Key Characteristics:**
- Near-black ground (`#121212`) matching the logo icon's own background, not a generic dark-SaaS near-black chosen by category.
- Logo blue (`#1475fc`) at Committed intensity: button fills, badge fills, active/progress states, one emphasized headline word — not restrained to link text.
- Bold, expressive display face (Bricolage Grotesque) for headlines; native system font (SF Pro / system-ui) for everything meant to read as the OS's own voice.
- A faithful interactive product recreation in the hero with one linear quota card per enabled provider, never a generic dashboard mockup.
- Rounded, pill-shaped interactive elements (buttons, badges) against otherwise rectilinear panels with soft continuous corners (14-20px) — matching real macOS card language, not the previous world's flat/sharp-cornered document language.

## Colors

Near-black ground, one committed blue, sparing warm-white text.

### Primary
- **Codex Blue** (`#1475fc`): the logo's own blue, used at Committed scale — primary button fills, the accent word in the display headline, active toggle/progress states, badge fills, checkmarks, focus rings. This is the page's one saturated color; every other hue is neutral.

### Neutral
- **Ground** (`#121212`): the page background, sampled to match the logo icon's own dark fill.
- **Raised** (`#1b1b1d`): card and panel backgrounds — feature cards, the FAQ accordion, the screenshot frame.
- **Inset** (`#0c0c0d`): recessed surfaces — code blocks, the badge strip background.
- **Border** (`#2a2a2d`): 1px hairlines on cards, dividers, input/accordion edges.
- **Menu Bar Black** (`#060606`): the real menu bar strip's own background inside its frame — darker than the page ground, matching the actual screenshot.
- **On Accent** (`#ffffff`): text and focus outlines set directly on Codex Blue or on the dark ground.
- **Hairline Highlight** (`rgba(255,255,255,0.08)`): the 1px inset edge on the popover frame, simulating a vibrancy panel's light catch.
- **Text** (`#f3f3f1`): headlines and primary body copy.
- **Text Dim** (`#9c9c98`): secondary copy, subheads, captions.
- **Text Faint** (`#828280`): tertiary meta (footer fine print, timestamps). Lightened from an earlier `#686865` during polish: the original value read at 3.35:1 on the page ground, below WCAG AA's 4.5:1 floor for the small text it's actually used on (install notices, meta lines, footer disclaimer).

### System Chrome (exempt from the palette)
- **Traffic Lights** (`#ff5f57` red, `#febc2e` yellow, `#28c840` green): the literal macOS window-control dot colors, used only on the titlebar of the Settings/Update/Install-help window recreations. These are Apple's own system colors, not part of the product palette, and never appear anywhere else on the page.

### Named Rules
**The Committed Blue Rule.** Codex Blue fills real surfaces — buttons, badges, active states — at a scale visible from across the page. It is never reduced to a thin link color; that would undo the "Committed" intensity the user explicitly chose.

## Typography

**Display Font:** Bricolage Grotesque (falls back to SF Pro Display, system-ui)
**Body Font:** -apple-system / SF Pro Text (system-ui stack)
**Label/Mono Font:** SF Mono (falls back to ui-monospace, Menlo)

**Character:** A bold geometric display face carries headline confidence (the Chimlo-bar quality); the system font stack carries everything meant to feel like it belongs to macOS itself — body copy, buttons, UI labels.

### Hierarchy
- **Display** (700, clamp(2.5rem, 6vw, 4.25rem), 1.05): the hero headline only.
- **Headline** (700, clamp(1.75rem, 3.5vw, 2.5rem), 1.15): section headings (Features, Private by design, Install, FAQ, closing CTA).
- **Body** (400, 1.0625rem, 1.6): all reading paragraphs, capped at 65ch.
- **Lede** (400, 1.125rem, 1.6): the hero subhead only — one step larger than body for the single most important paragraph on the page.
- **Card title** (600, 1.5rem, 1.25, display face): the "difference card" heading inside Features.
- **Label** (600, 0.8125rem, 1.4, mono, 0.06em tracking, uppercase): eyebrows, badges, meta lines.
- **UI small** (400, 0.9375rem, 1.5): nav links, feature-card body, checklist items.
- **UI small tight** (600, 0.9688rem, 1.4): the feature-list row title and the checkbox label text — one hair above UI small, for label weight without jumping a full step.
- **UI caption** (600, 0.875rem, 1.4): small buttons, the reads-strip line.
- **Micro** (600, 0.75rem, 1.4, mono, 0.05em tracking, uppercase): badge pill text.
- **Nano** (600, 0.6875rem, 1.3, mono, 0.04em tracking, uppercase): the "PLUS" tier pill inside the live usage popover — one step below Micro, scaled to the demo's own smaller frame.
- **Glyph** (display face, 1.25rem): the accordion's own +/&minus; indicator only, sized against the summary line it sits beside rather than the body ramp.

### Named Rules
**The Two-Voice Rule.** Bricolage Grotesque only ever sets a headline. Every paragraph, button label that isn't a badge, and UI-adjacent string sets in the system font stack.

## Layout

Full-bleed dark canvas; content constrained to a 1200px max-width container with responsive gutters (32px desktop, 20px mobile). Hero is two-column on desktop (copy left, screenshot frame right) and stacks on mobile. Sections separate by generous vertical rhythm (96px between major sections desktop, 48px mobile), not by rule lines — depth comes from raised panels, not hairlines, in this world. Feature grid is 2-column on desktop, 1-column on mobile.

## Elevation & Depth

Layered, not flat: raised panels (`#1b1b1d`) sit on the ground (`#121212`) with a 1px border (`#2a2a2d`) plus a soft, low-contrast shadow for separation — never a bright colored glow. The screenshot frame additionally uses a subtle vibrancy-style backdrop blur where it overlaps the ground, echoing real macOS panel material.

### Shadow Vocabulary
- **Card ambient** (`box-shadow: 0 1px 2px rgba(0,0,0,0.4), 0 12px 32px rgba(0,0,0,0.35)`): feature cards, the screenshot frame, the FAQ accordion.
- **Button lift** (`box-shadow: 0 1px 2px rgba(0,0,0,0.3)`): primary button at rest; no hover glow, only a background-color shift.

### Named Rules
**The No-Glow Rule.** Depth comes from a neutral dark shadow and a border, never a colored halo around the accent. A blue glow reads as the generic dark-SaaS rut this system explicitly avoids.

## Shapes

Pill-radius (999px) on every interactive control — buttons, badges, nav pills. Cards and panels use a soft continuous corner (14-20px), never sharp. Inline code and the smallest chips use a tighter 6px radius, matching a real system text-field/token corner rather than the page's card corner. The hand-drawn battery glyph in the live menu bar demo uses 1-2px radii on its own tiny strokes (the icon body and its nub) — scaled to the glyph, not the card system. Settings switches and radio controls follow native macOS proportions. This is a deliberate reversal from the previous flat-document world: the new world speaks real macOS card language.

## Components

### Buttons
- **Shape:** full pill radius (999px).
- **Primary:** Codex Blue fill (`#1475fc`), white text, 14px/28px padding, system-font label at 600 weight.
- **Hover / Focus:** background shifts to `#3b8bff`; focus-visible adds a 2px white outline offset 2px on the dark ground (never color-only).
- **Ghost/Secondary:** transparent fill, 1px border (`#2a2a2d`), text color `#f3f3f1`; hover raises background to `#1b1b1d`.

### Badges / Pills
- **Style:** `accent-tint` background (`rgba(20,117,252,0.14)`), Codex Blue text, mono label type, pill radius, thin transparent-to-border edge.
- **Use:** eyebrows above headlines, the "reads only ~/.codex/auth.json" strip, compatibility markers.

### Cards
- **Corner Style:** 14-20px continuous radius.
- **Background:** `#1b1b1d` on `#121212` ground.
- **Shadow Strategy:** Card ambient (see Elevation).
- **Border:** 1px `#2a2a2d`.
- **Internal Padding:** 24-32px.

### Live Usage Demo (signature component)
- The hero recreates the menu-bar summary and the multi-provider popover. Each enabled provider has its own compact card with branded identity, quota percentage, reset detail, and linear progress bars. The large circular popover meter is retired; the small menu-bar ring remains the most-constrained-provider summary.
- The Settings overlay recreates the current General, Authentication, Notifications, and About toolbar panes. Canonical captures in `docs/assets/screenshots/` use the same structure and controlled sample values as the live demo.

### Checklist (privacy section)
- Each row: a filled Codex Blue circular checkmark (16px), body-weight text, no strike-through — this world proves the no-access claim by affirmation ("No Chrome access") rather than the previous world's strike-through negation.

### Navigation
- Logo mark + wordmark left; text links (system font, 0.9375rem) center/right; primary pill button plus two compact icon buttons (install-help, GitHub) right-most. Sticky, with a persistent blurred translucent background and a 1px bottom hairline rather than a scroll-triggered shadow — simpler, and consistent with the No-Glow/flat-card language elsewhere.

## Do's and Don'ts

### Do:
- **Do** keep Codex Blue at Committed scale — real fills, not thin accents.
- **Do** use Bricolage Grotesque for headlines only; everything else is system font.
- **Do** present real screenshots for every product claim that can show, not just tell.
- **Do** use pill radius on every button and badge; soft continuous radius on every card.

### Don't:
- **Don't** add a colored glow or neon halo around the accent — depth is a neutral shadow, not a blue aura.
- **Don't** introduce a second saturated accent color.
- **Don't** use sharp/zero-radius corners anywhere in this world (that was the previous man-page world; this one is deliberately softer).
- **Don't** copy Chimlo's copy, mascot, or green accent — only its structural confidence and section rhythm.
