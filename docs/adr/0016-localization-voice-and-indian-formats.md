# ADR-0016: ARB-based localisation, recorded voice clips plus TTS for names, Indian formats

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Product, Design, Engineering
- **Related:** FR-L10N-01..06 · FR-ENR-02 · FR-DPR-04 · NFR-UX-01 · Designs 01–05, 13 · ADR-0005

## Context

Workers may not read well, and they speak different languages in different clusters. Owners often prefer Hindi or their regional language for admin too. The PRD requires:

- English + Hindi at GA,
- Gujarati, Tamil, Punjabi, Marathi at each cluster's launch,
- voice prompts at the gate,
- worker notices in the worker's language,
- Indian date and number formats,
- externalised strings.

## Decision

### 1. Strings

- Flutter **gen-l10n** with **ARB** files in `sg_l10n` and ICU MessageFormat for plurals and gender (e.g. `{count, plural, one{1 record needs review} other{{count} records need review}}`).
- Locales: `en_IN`, `hi_IN` at GA; `gu_IN`, `ta_IN`, `pa_IN`, `mr_IN` added per cluster launch. Adding a language means adding an ARB file plus voice clips, with **no code change** (FR-L10N-06).
- **Three language settings** (FR-L10N-04):

| Setting | Controls |
|---|---|
| Device language | Gate-mode prompts and default UI |
| Admin user language | Admin screens for that user |
| Worker language | That worker's gate greeting, voice prompt and privacy notice |

- Translations are done by **professional translators plus field review** with workers in each cluster. Plain words are preferred over formal Sanskritised Hindi (e.g. "हाज़िरी", not "उपस्थिति").
- Legal notice text (CMP-01, CMP-09) is versioned (`notice_version`) and reviewed by counsel in each language.

### 2. Voice prompts (FR-L10N-03)

| Prompt | Source |
|---|---|
| Fixed phrases: "IN", "OUT", "Welcome", "Try again", "Already marked", "Come closer", "Clean the camera", "Blink once" | **Pre-recorded clips** per language (Opus, ~5 KB each), played with `just_audio` and pre-loaded at gate start for zero latency |
| Worker's **name** ("रमेश, इन") | **On-device TTS** (`flutter_tts` → Android `TextToSpeech` / iOS `AVSpeechSynthesizer`) when a voice for that language is installed; otherwise phrase clip only |
| Privacy notice "Read aloud" (design 13) | Recorded clip per notice version and language (preferred); TTS fallback |
| Success / failure tones | Distinct earcons (rising for success, low double for failure), so meaning is clear without words |

- Setup checks the available TTS voices and warns if the worker languages lack one. Hindi is broadly available (Google TTS on Android; iOS `hi-IN`). Coverage for Tamil, Gujarati, Punjabi and Marathi varies, especially on iOS, which is why fixed phrases are always recorded.
- Volume: the gate uses the media stream at a configured level (default 80%). A "quiet hours" option is available.

### 3. Formats (FR-L10N-05)

| Item | Format |
|---|---|
| Date | **DD-MM-YYYY** everywhere (24-10-2026); weekday abbreviations localised |
| Time | 12-hour with AM/PM by default; 24-hour toggle |
| Numbers | Indian grouping via `intl` `en_IN` (1,23,456) |
| Digits | Western Arabic digits by default, even in Hindi UI (field research: workers read them faster); native digits as an option |
| Names | Stored as typed (Unicode NFC). Sorting uses a locale-aware collator. Search matches transliterations (Latin ↔ Devanagari) with a small built-in transliteration table. |

### 4. Layout

- All screens are tested at **130% text scale** and with the longest translation (often Tamil). Buttons wrap rather than truncate.
- All Phase 1 languages are left-to-right; no RTL work is needed.

## Options considered

| Option | Verdict |
|---|---|
| TTS for everything | Rejected: inconsistent quality and availability on budget phones and iOS for regional languages. |
| Recordings for everything, including names | Impossible for arbitrary names. |
| Icons and colours only | Insufficient alone. Kept as a parallel channel. |

## Consequences

- Each new language costs translation, legal review and ~20 voice clips (roughly one studio day).
- Golden tests run in all shipped locales for key screens.
