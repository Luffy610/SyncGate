# ADR-0022: Opt-in, PII-free crash reports and an exportable diagnostic bundle

- **Status:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Support, Legal
- **Related:** NFR-OPS-03, NFR-OPS-04 · FR-LIC-05 · TC-01 · ADR-0014, ADR-0017, ADR-0020

## Context

We need to fix crashes and help owners remotely. But the product promise is that the vendor **does not process worker personal data** (§9.1), and support must work for owners on WhatsApp who cannot describe technical problems.

## Decision

### 1. Crash reporting (opt-in)

- **Sentry** (`sentry_flutter`, native SDKs for Kotlin/Swift crashes). It is **off by default**. The owner opts in during setup with a plain-language explanation, and can change it in Settings › Privacy.
- Data residency: Sentry EU/US SaaS is acceptable for **non-personal** diagnostics; a self-hosted option is reviewed if legal prefers India-only.
- **Scrubbing:**
  - `beforeSend` / `beforeBreadcrumb` drop all user-entered strings;
  - worker names, IDs and phone numbers are never logged (release builds use a logger that accepts only enumerated event codes plus numbers);
  - no screenshots and no view hierarchy attachments;
  - `sendDefaultPii = false`;
  - IP address not stored (server-side scrubbing on).
- What is sent: stack trace, app version/flavour, OS version, device model, free memory, thermal state, pipeline stage timings, licence ID hash (to correlate with support tickets).

### 2. On-device logs

- A rotating **encrypted** log (5 × 1 MB) of enumerated events: mode changes, pipeline stats per minute, thermal and battery state, errors with codes, backup and export results.
- Never contains frames, scores linked to names, or personal data. Worker IDs appear only as **salted hashes**, so the owner can match them if needed and we cannot.

### 3. Diagnostic bundle (NFR-OPS-04)

- Settings › Help › "Send diagnostics to support" builds a `.sgdiag` zip containing:
  - device info, app/model versions, settings (no personal fields), licence state;
  - the last 7 days of on-device logs;
  - aggregate gate metrics: marks per day, not-recognised rate, manual-entry rate, liveness-active rate, gate uptime vs schedule, thermal events;
  - DB integrity and audit-chain status.
- The owner **previews the content** in-app before sharing it through the share sheet (usually WhatsApp to the support number).
- No personal or biometric data. An automated test asserts the bundle schema (same check as the outbound-schema test, [ADR-0017](0017-security-hardening-and-privacy-dpdp.md)).

### 4. Product analytics

**None in Phase 1.** No Firebase Analytics, no third-party SDKs that phone home. Product learning comes from the beta interviews and the aggregate metrics owners choose to share.

### 5. Support model

| Channel | Use |
|---|---|
| WhatsApp Business number | First line in Hindi/English; regional languages by cluster |
| Setup videos (Hindi + regional) | Self-serve onboarding (§5.3) |
| Diagnostic bundle | Technical triage |
| Support console (licence server, internal) | Licence lookup, transfer, lost-device revoke, root-detection override — all actions audit-logged |

## Options considered

| Option | Verdict |
|---|---|
| Firebase Crashlytics + Analytics | Rejected: analytics conflicts with the privacy positioning. Crashlytics alone is viable, but Sentry's scrubbing hooks and self-host option fit better. |
| No crash reporting at all | Rejected: we could not keep budget-device crash rates low. |
| Remote log upload | Rejected: owner-initiated sharing only. |

## Consequences

- Crash visibility depends on opt-in rates. Beta factories are asked to opt in.
- Support cannot see customer data, by design. Troubleshooting relies on the bundle plus a video call when needed.
