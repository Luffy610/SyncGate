# ADR-0005: One brand design system with platform-adaptive chrome; bundled fonts

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Design, Engineering
- **Related:** PRD §4.2 (pillar 3), FR-L10N-01..03, NFR-UX-01..04 · Designs in [`docs/designs`](../designs) · ADR-0002, ADR-0016

## Context

SyncGate is used by three very different people: workers glancing at a screen for under a second, a guard fixing exceptions, and an owner doing admin. It must:

- feel at home on both iOS and Android (owners are used to their own phone),
- look like one brand across both,
- render Hindi and regional scripts correctly on cheap phones,
- work **with no internet**, which rules out loading web fonts at runtime.

## Decision

### 1. One brand, platform-native chrome

The **content and brand** are shared. The **chrome** follows each platform:

| Element | iOS (Cupertino conventions) | Android (Material 3 conventions) |
|---|---|---|
| Top bar | Large title on tab roots; centred 17 pt title on pushed screens; text buttons ("Cancel", "Next", "‹ Back") | Small top app bar, left-aligned 22 sp title, icon buttons (← back, ✕ close, ⋮ overflow) |
| Bottom navigation | Tab bar, 83 pt, hairline top border, active icon filled | Navigation bar, 80 dp, **pill active indicator** in brand yellow |
| Primary action placement | "+" in the nav bar (Enrol) | **Extended FAB** "Enrol worker" |
| Buttons | Rounded rectangle, radius 12, height 50 | Full pill, radius 24, height 48 |
| Text fields | Grouped inset rows (label left, value right) | **Outlined** fields with floating labels |
| Selection | Checkmark on the selected row | Radio buttons / checkboxes |
| Switches | iOS switch (51×31, green track) | M3 switch (52×32, thumb with check icon) |
| Segmented choice | Segmented control | Segmented buttons with check icon |
| Sheets | Sheet with grabber, Cancel/Save in header | Modal bottom sheet, drag handle, actions at bottom |
| Share icon | Square with up arrow | Three connected nodes |
| Biometric unlock | Face ID glyph | Fingerprint glyph |
| Kiosk copy | Guided Access | App pinning |

Implementation: `sg_ui` exposes **adaptive components** (`SgTopBar`, `SgNavBar`, `SgButton`, `SgSwitch`, `SgTextField`, `SgSheet`, `SgSegmented`, `SgSelectRow`). Each switches on `Theme.of(context).platform`. Screens use only `sg_ui` components, never raw `Cupertino*` / `Material` widgets, so platform differences live in one place. Every component has golden tests for both platforms ([ADR-0020](0020-testing-strategy-and-ml-evaluation.md)).

### 2. Design tokens

| Token | Value | Use |
|---|---|---|
| `ink` | `#15171A` | Primary text, primary buttons |
| `ground.ios` / `ground.android` | `#F2F1ED` / `#F7F6F2` | Screen background |
| `surface` | `#FFFFFF` | Cards, lists |
| `line` | `#E6E4DD` | Card borders, dividers |
| `muted` | `#5E615F` | Secondary text (≥4.5:1 on white) |
| `brand.yellow` | `#FFC21A` | Brand mark, active nav indicator, gate scan brackets, primary on dark. **Fill only — never as text on light backgrounds.** |
| `gate.bg` / `gate.panel` | `#101214` / `#16191C` | Gate mode (dark) |
| `success` | `#0E7A45` (fill) · `#0B7A43` (text) | Matched IN/OUT, OK checks |
| `danger` | `#A8261C` | Not recognised, destructive actions |
| `warning` | bg `#FDF0D2`, text `#6B4100`/`#7A4A00`, icon `#B26A00` | Low light, backup overdue, missing OUT |
| `info` | bg `#E7ECF8`, text `#1F3F8F` | Manual-entry tags |
| Radii | iOS 12 · Android 16 (cards); chips 18/8 | |
| Spacing | 4-pt grid; screen gutter 16–20 | |

All text/background pairs are checked for **WCAG AA** (4.5:1 body, 3:1 for ≥24 px). Status is **never colour-only**: green has a ✓ icon, red has ✕, amber has ⚠, plus a voice prompt in gate mode (NFR-UX-04, FR-L10N-03).

### 3. Typography and fonts — bundled, never fetched

| Family | Script | Licence |
|---|---|---|
| IBM Plex Sans (400/500/600/700) | Latin | SIL OFL 1.1 |
| IBM Plex Sans Devanagari (400/500/600/700) | Hindi, Marathi | SIL OFL 1.1 |
| Noto Sans Gujarati (500/600) | Gujarati | SIL OFL 1.1 |
| Noto Sans Tamil (500/600) | Tamil | SIL OFL 1.1 |
| Noto Sans Gurmukhi (500/600) | Punjabi | SIL OFL 1.1 |
| IBM Plex Mono (500/600) | IDs, times, licence keys | SIL OFL 1.1 |

- Fonts ship **inside the app** (`sg_ui/assets/fonts`). No Google Fonts requests at runtime. The app must render perfectly offline.
- A font **fallback chain** is set on the root `TextTheme`, so mixed-script strings (e.g. "Continue · आगे बढ़ें") render correctly.
- Latin fonts are **subset** to the characters we need. Regional fonts are kept whole for shaping correctness. Budget: ≤6 MB of fonts total.
- Type scale: gate prompt 30/44 (Hindi first, English second), gate name 38, titles 34 (iOS large title) / 22–28 (Android), body 15–16, captions 12–13. Nothing below 11 px.

### 4. Gate-mode visual language

- Dark background so the camera preview and confirmation colour stand out, and to reduce glare and power on OLED screens.
- Full-area **green** for a match and **red** for no match. Both are readable at 0.6–1 m.
- **Hindi (or the device language) first, English second** for all worker-facing text.
- No face image is shown after the match. Only initials appear in lists, which reinforces "no photos stored".

### 5. Source of truth

- The canvas design is the source of truth: <https://claude.ai/artifact/8pZEg6Qb8Hkv3hZj1QG5nK>. PNG exports live in [`docs/designs/ios`](../designs/ios) and [`docs/designs/android`](../designs/android) (17 screens each, same file names).
- Token values above are mirrored in `sg_ui/lib/tokens.dart`. A change to a token is a design review item.

## Options considered

| Option | Verdict |
|---|---|
| Pure Material 3 on both platforms | Rejected: iOS owners find it foreign; App Store reviewers sometimes flag poor platform fit. |
| Fully native look per platform (no shared brand) | Rejected: doubles design work; weak brand. |
| Load Google Fonts at runtime | Rejected: breaks offline-first. |
| System fonts only | Rejected: Devanagari and Tamil quality varies widely across Android OEMs. |

## Consequences

- Two golden-test baselines per component.
- Design hand-off includes both platform variants for every new screen, as in the current canvas.
