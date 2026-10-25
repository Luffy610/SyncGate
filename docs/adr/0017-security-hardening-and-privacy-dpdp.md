# ADR-0017: Security hardening and DPDP-by-design controls

- **Status:** In review
- **Proposed outcome:** Accepted (legal interpretations pending: TBD-L1, TBD-L3)
- **Date:** 24-10-2026
- **Deciders:** Security, Engineering, Legal, Product
- **Related:** PRD §9 (CMP-01..10), NFR-SEC-01..06, NFR-OPS-03, TC-01, TC-07 · Risks R-3, R-7, R-10 · ADR-0010, ADR-0011, ADR-0013, ADR-0014

> This ADR lists **product and engineering controls**. It is not legal advice. Counsel must validate it against the DPDP Act, 2023 and the notified Rules before GA.

## Context

The factory owner is the **Data Fiduciary**. SyncGate (the vendor) is designed **not to process worker personal data at all** (§9.1). Penalties reach ₹250 crore, and breaches must be reported within 72 hours. The owner has no compliance function. So the product must make the right thing the default.

## Decision

### 1. Threat model (summary)

| Threat | Actor | Controls |
|---|---|---|
| Proxy attendance with photo/screen/video | Worker | Liveness ([ADR-0007](0007-liveness-detection.md)), multi-frame matching ([ADR-0009](0009-face-matching-and-thresholds.md)), spoof-attempt exceptions |
| Guard marks absent friends manually | Guard | Required reason, per-worker daily cap, flagged in reports, owner review |
| Clock manipulation | Guard / worker | Monotonic checks + trusted time ([ADR-0012](0012-time-shifts-and-attendance-rules-engine.md)) |
| Editing records | Admin / insider | Append-only tables + hash chains ([ADR-0011](0011-data-model-append-only-events.md)) |
| Lost or stolen phone | Anyone | Device-bound encryption, kiosk lock, remote revoke + wipe ([ADR-0013](0013-backup-restore-and-device-replacement.md)) |
| Rooted phone / tampered APK | Technical attacker | Integrity checks (below), template features disabled on compromised devices |
| Data leak through backups, logs, crash reports | Accidental | Templates excluded by architecture; PII scrubbing; logs never contain names or IDs in release builds |
| Network interception | Attacker | TLS 1.3, certificate pinning to the licence server |

### 2. Device and app integrity (NFR-SEC-05)

- **Android:** Play Integrity API (`MEETS_DEVICE_INTEGRITY`) at activation and each check-in. Local root heuristics (su binaries, Magisk traces, test-keys, writable `/system`, Frida/Xposed hooks) via **freeRASP** (Talsec) or an equivalent in-house check. `FLAG_SECURE` on admin screens showing personal data (blocks screenshots and recents thumbnails). The gate screen is also `FLAG_SECURE`, because it shows names.
- **iOS:** App Attest. Jailbreak heuristics (sandbox escape checks, suspicious dylibs, URL schemes). Admin screens are blurred in the app switcher.
- **On a compromised device:** gate matching and enrolment are **disabled**. Admin, reports, export and backup stay available, so data can be moved to a clean phone. The owner sees why.
- Release builds: R8/ProGuard + Dart `--obfuscate --split-debug-info`; debuggable off; no `android:usesCleartextTraffic`.

### 3. Network

- The only endpoints are the **licence server** and **Google APIs** (Sign-In, Drive), plus opt-in Sentry ([ADR-0022](0022-telemetry-diagnostics-and-support.md)). Android uses an explicit Network Security Config allow-list. iOS uses ATS with no exceptions.
- The licence server is SPKI-pinned (primary + backup).
- **Automated test:** a CI check inspects every outbound request schema. Any field resembling `embedding`, `template`, `face`, `image` or `photo`, or a worker name/ID, fails the build (TC-01 enforcement).

### 4. DPDP controls mapped to features

| CMP | Control | Where |
|---|---|---|
| CMP-01 Notice | Itemised notice in the worker's language, read-aloud, versioned | Design 13, [ADR-0008](0008-enrolment-and-template-management.md), [ADR-0016](0016-localization-voice-and-indian-formats.md) |
| CMP-02 Legal basis | Recorded per worker with timestamp; configurable (consent vs legitimate use, TBD-L1) | `consents` table |
| CMP-03 Purpose limitation | Templates only usable by the native matcher; no API to read vectors | [ADR-0003](0003-app-architecture-and-repository-layout.md), [ADR-0010](0010-local-storage-and-encryption.md) |
| CMP-04 Minimisation | No images stored; events hold scores, not pictures; optional fields really optional | [ADR-0006](0006-on-device-vision-pipeline.md), [ADR-0011](0011-data-model-append-only-events.md) |
| CMP-05 Retention / erasure | Configurable retention (TBD-L3); 90-day template auto-delete after exit | [ADR-0011](0011-data-model-append-only-events.md) |
| CMP-06 Safeguards | AES-256 at rest, TLS in transit, roles, PINs, audit log | [ADR-0004](0004-single-device-gate-and-admin-modes.md), [ADR-0010](0010-local-storage-and-encryption.md) |
| CMP-07 Breach readiness | Lost-device incident record, remote revoke + wipe, pre-filled 72-hour notification template | [ADR-0013](0013-backup-restore-and-device-replacement.md) |
| CMP-08 Worker rights | Data summary, correction, erasure, grievance contact | [ADR-0011](0011-data-model-append-only-events.md) §5, Settings |
| CMP-09 Compliance pack | In-app "DPDP pack": data-flow diagram, data inventory, security summary, notice templates in all languages, exportable as PDF | Settings › Privacy |
| CMP-10 Children | DOB required; under-18 enrolment blocked; owner alerted | Design 12 |

### 5. Assurance before GA (NFR-SEC-06)

- Independent **penetration test** (mobile app + licence server), following the OWASP MASVS L2 checklist.
- **Biometric privacy review** by an external reviewer.
- Store disclosures reviewed ([ADR-0021](0021-build-ci-cd-release-and-store-compliance.md)).
- No open Sev-1/Sev-2 findings at GA.

## Consequences

- `FLAG_SECURE` on the gate screen means owners cannot screenshot it for support. The diagnostic bundle covers support needs instead ([ADR-0022](0022-telemetry-diagnostics-and-support.md)).
- Root detection has false positives on some custom ROMs. Support can issue a per-device override that is logged on the server.
