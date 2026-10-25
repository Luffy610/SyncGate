# SyncGate — Architecture Decision Records (Phase 1)

This folder records every significant product, design and technical decision for **SyncGate Phase 1**. Each record (ADR) explains the context, the decision, the options we weighed and the consequences, so that anyone joining later can see *why* the system looks the way it does.

| Field | Value |
|---|---|
| Product | SyncGate — Smart Attendance Tracker |
| Phase | Phase 1 (v1 / GA) |
| Source documents | [PRD](../PRD.md) · [Screen designs (iOS)](../designs/ios) · [Screen designs (Android)](../designs/android) · [Phase 1 delivery plan](../delivery/phase-1-delivery-plan.md) |
| Last updated | 24-10-2026 |
| Owner | Product Management + Engineering |

---

## 1. Phase 1 in one paragraph

SyncGate Phase 1 turns **one ordinary Android or iOS phone** into a complete attendance system for a **small factory of up to 25 workers**. The same phone is the **gate kiosk** (hands-free face attendance), the **enrolment station** and the **owner's admin console** (shifts, corrections, reports, payroll export, backup). Everything runs **fully offline**. Face templates are created, stored and matched **only on that phone** and never leave it. The owner exports shift-processed attendance to **Excel and Tally Prime**. Internet is used only for licence check-ins and the owner's optional encrypted backup to their own Google Drive.

> **Scope change from PRD v0.2:** the PRD describes one 8–10" tablet serving 50–200 workers. Phase 1 has been narrowed to **one phone, ≤25 workers** (see [ADR-0001](0001-phase-1-scope-one-phone-25-workers.md)). PRD requirements that assume tablets or 200-worker throughput are restated in the ADRs below.

---

## 2. Status legend

> **Current state:** every Phase 1 ADR is **In review**. The "Proposed outcome" column shows the status each record will take once its named deciders approve it.

| Status | Meaning |
|---|---|
| **In review** | Written and open for review by the deciders named in the ADR. Prototypes may start against it, but nothing is final. The record's "Proposed outcome" says what it will become if approved. |
| **Accepted** | Decided. Build against it. Change only through a new ADR that supersedes it. |
| **Proposed** | Our recommended direction. Build prototypes against it. It is confirmed or changed at the gate named in the ADR (usually the M0 feasibility spike). |
| **Open** | A decision we know we need but cannot take yet (usually legal or commercial). |
| **Superseded** | Replaced by a later ADR (link given). |

---

## 3. Decision log

| # | Decision | Status | Proposed outcome | Area |
|---|---|---|---|---|
| [0001](0001-phase-1-scope-one-phone-25-workers.md) | Phase 1 scope: one phone, one gate, up to 25 workers, fully offline | In review | Accepted | Product |
| [0002](0002-cross-platform-framework-flutter.md) | Flutter for the app UI, with native camera and ML modules | In review | Proposed (confirm at M0) | Platform |
| [0003](0003-app-architecture-and-repository-layout.md) | Layered, modular app architecture and monorepo layout | In review | Accepted | Architecture |
| [0004](0004-single-device-gate-and-admin-modes.md) | One device, two modes (Gate kiosk and Admin), with roles and OS kiosk locking | In review | Accepted | Product / Architecture |
| [0005](0005-design-system-and-platform-adaptive-ui.md) | One brand design system with platform-adaptive chrome; bundled fonts | In review | Accepted | Design |
| [0006](0006-on-device-vision-pipeline.md) | On-device vision pipeline on LiteRT: detection, quality, alignment, embedding | In review | Proposed (confirm at M0) | ML |
| [0007](0007-liveness-detection.md) | Passive liveness by default, with an optional active fallback | In review | Proposed (confirm at M0) | ML / Security |
| [0008](0008-enrolment-and-template-management.md) | Guided multi-angle enrolment; several templates per worker; no raw images kept | In review | Accepted | ML / Privacy |
| [0009](0009-face-matching-and-thresholds.md) | Exact 1:N cosine matching with margin and multi-frame agreement | In review | Accepted | ML |
| [0010](0010-local-storage-and-encryption.md) | Encrypted SQLite (SQLCipher via Drift) and a separate template vault, keys in Keystore/Keychain | In review | Accepted | Data / Security |
| [0011](0011-data-model-append-only-events.md) | Append-only attendance events, corrections as new records, hash-chained audit log, UUIDv7 IDs | In review | Accepted | Data |
| [0012](0012-time-shifts-and-attendance-rules-engine.md) | Pure-Dart shift and rules engine; time model and clock-integrity checks | In review | Accepted | Domain |
| [0013](0013-backup-restore-and-device-replacement.md) | Passphrase-encrypted backups (no biometrics) to a local file or the owner's Google Drive | In review | Accepted | Data |
| [0014](0014-licensing-and-licence-server.md) | Ed25519-signed offline licence tokens; a minimal metadata-only licence server in India | In review | Proposed (stack) / Accepted (model) | Commercial / Backend |
| [0015](0015-reports-and-payroll-export.md) | On-device reports; Excel (.xlsx) and Tally Prime XML exports through the OS share sheet | In review | Accepted | Product |
| [0016](0016-localization-voice-and-indian-formats.md) | ARB-based localisation, recorded voice clips plus TTS for names, Indian formats | In review | Accepted | Product / Design |
| [0017](0017-security-hardening-and-privacy-dpdp.md) | Security hardening and DPDP-by-design controls | In review | Accepted | Security / Compliance |
| [0018](0018-power-thermal-and-reliability-on-a-phone.md) | Duty-cycled camera, wake/thermal management, crash recovery, paper fallback | In review | Accepted | Reliability |
| [0019](0019-supported-devices-and-os-versions.md) | Supported phones and OS versions; reference device certification | In review | Proposed (device list at M0) | Platform |
| [0020](0020-testing-strategy-and-ml-evaluation.md) | Test pyramid, device lab and a biometric evaluation harness | In review | Accepted | Quality |
| [0021](0021-build-ci-cd-release-and-store-compliance.md) | GitHub Actions + Fastlane, flavours, signing, store compliance | In review | Accepted | Delivery |
| [0022](0022-telemetry-diagnostics-and-support.md) | Opt-in, PII-free crash reports and an exportable diagnostic bundle | In review | Accepted | Operations |

---

## 4. Tech stack at a glance (Phase 1)

| Layer | Choice | ADR |
|---|---|---|
| App framework | **Flutter** (Dart 3, stable channel), one codebase for Android and iOS | 0002 |
| UI | Custom brand widgets; Material 3 chrome on Android, Cupertino chrome on iOS | 0005 |
| State management | **Riverpod** (`flutter_riverpod`, code-gen providers) | 0003 |
| Navigation | **go_router** with a mode-aware redirect (Gate / Admin / Setup) | 0003, 0004 |
| Native bridge | **Pigeon**-generated type-safe platform channels; Flutter `Texture` for camera preview | 0002, 0006 |
| Camera | **CameraX** (Android, Kotlin) · **AVFoundation** (iOS, Swift) | 0006 |
| ML runtime | **LiteRT** (formerly TensorFlow Lite) on both platforms; XNNPACK CPU by default, GPU delegate optional | 0006 |
| Face detection | BlazeFace short-range-class model (Apache-2.0), run directly on LiteRT | 0006 |
| Face recognition | MobileFaceNet-class embedding model, INT8, ~1–5 MB — **weights must carry a commercial licence (TBD-L2)** | 0006 |
| Liveness | Passive texture/frequency CNN + multi-frame cues; optional blink challenge as fallback | 0007 |
| Local database | **SQLite** via **Drift**, encrypted with **SQLCipher** (`sqlcipher_flutter_libs`), WAL mode | 0010 |
| Secrets | Android Keystore (StrongBox when present) · iOS Keychain (+ Secure Enclave wrapping key) via `flutter_secure_storage` / native code | 0010 |
| Crypto | AES-256-GCM, Argon2id (backup passphrase), Ed25519 (licence), SHA-256 (audit chain) via `cryptography` | 0010, 0011, 0013, 0014 |
| Backup | Encrypted `.sgbackup` file → OS share sheet (`share_plus`) and/or Google Drive (`drive.file` scope) | 0013 |
| Exports | `.xlsx` via the `excel` package; Tally Prime XML via the `xml` package | 0015 |
| Localisation | `flutter_localizations` + gen-l10n (ARB/ICU), `intl` with `en_IN` / `hi_IN` formats | 0016 |
| Voice | Recorded phrase clips (`just_audio`) + on-device TTS for names (`flutter_tts`) | 0016 |
| OS auth for admin | `local_auth` (Face ID / Touch ID / Android BiometricPrompt) on top of the PIN | 0004 |
| Device integrity | Play Integrity API (Android) · App Attest (iOS) · root/jailbreak checks | 0014, 0017 |
| Licence server | **Go** service, **PostgreSQL**, AWS **ap-south-1 (Mumbai)** | 0014 |
| Crash reporting | Sentry (`sentry_flutter`), **opt-in**, PII scrubbing in `beforeSend` | 0022 |
| Monorepo tooling | **Melos** | 0003 |
| CI/CD | **GitHub Actions** + **Fastlane**; Play internal track, TestFlight, signed sideload APK | 0021 |
| Testing | `flutter_test` (unit/widget/golden), **Patrol** (device integration), Firebase Test Lab, Python ML evaluation harness | 0020 |

---

## 5. What is in Phase 1

**Gate (kiosk) mode**
- Hands-free face attendance with passive liveness, IN/OUT derived automatically, 2-minute repeat cooldown.
- Green/red full-screen confirmation with icon, name, time and a voice prompt in the worker's language.
- Guard fallback: pick the worker from the "not marked yet" list, with a required reason. The entry is flagged.

**Setup wizard (owner, ≤30 minutes)**
- Language → licence activation (or 30-day trial) → first shift → camera and light check → kiosk lock (Guided Access / app pinning) → first worker.

**Admin mode (PIN + optional OS biometrics)**
- Today dashboard (present / absent / late / on premises, exceptions, backup reminder).
- Workers list, enrolment (details → notice and consent in the worker's language → multi-angle face capture), deactivate, re-enrol, delete.
- Exceptions review and corrections with a mandatory reason and an audit trail.
- Shifts: day and night shifts (night crossing midnight), grace, late, early exit, half day, minimum hours, breaks, overtime.
- Reports: daily view, monthly muster roll, exceptions report.
- Export: Excel (.xlsx) and Tally Prime XML, shared through the OS share sheet.
- Backup and restore (no biometrics), backup reminders, move to a new phone, report the phone lost.
- Worker rights: data summary, correction, erasure; automatic template deletion after exit.
- Roles: Owner, Admin, Gate operator.

**Languages:** English and Hindi at GA. Gujarati, Tamil, Punjabi and Marathi switch on with each cluster launch.

## 6. What is NOT in Phase 1 (deferred)

| Deferred item | Why | Earliest |
|---|---|---|
| More than one device per factory, any sync (LAN or cloud) | Single phone is enough for ≤25 workers; avoids template-sharing legal questions | Phase 2 |
| Multiple gates, multiple sites | Not needed by the target customer | Phase 2 |
| Factories above 25 workers | Throughput, UX and pricing are tuned for ≤25 | Phase 2 (tablet + multi-device) |
| Labour-contractor channel, partner portal | Distribution is direct to owners | Phase 2 |
| Web admin portal | Admin lives on the same phone | Phase 2+ |
| Evidence thumbnails (FR-ATT-08) | Privacy positioning (D-4) | Post-GA decision |
| Rotating shifts, holiday calendars, leave marking, CSV bulk import | P1 priority in PRD | M4 (post-GA) |
| In-app UPI renewal | P1 priority in PRD | M4 (post-GA) |
| Statutory register formats | P2 | Later |
| Turnstiles, door relays, visitor or canteen management | Non-goals | — |

## 7. Open questions that block or shape decisions

| ID | Question | Affects |
|---|---|---|
| D-2 | Confirm Flutter after the M0 camera + ML benchmark on reference phones | 0002, 0006 |
| D-3 | Price point and trial terms; is "25 workers" a licence limit or only a sizing guide? | 0001, 0014 |
| D-5 | Tally Prime only, or Tally ERP 9 too? (Phase 1 proposal: Prime only) | 0015 |
| TBD-L1 | Legal basis for biometric processing (consent vs legitimate use) | 0008, 0017 |
| TBD-L2 | Commercial licence for face detection, recognition and liveness models and their training data | 0006, 0007 |
| TBD-L3 | Wage-record retention periods by state | 0011, 0017 |
| New | Kiosk behaviour after reboot/crash without MDM on each OS (verify in M0) | 0004, 0018 |
| New | Quality of Hindi and regional TTS voices on budget phones and iPhones | 0016 |

## 8. How to add or change an ADR

1. Copy the template below into a new file `NNNN-short-title.md` with the next number.
2. Open it as **In review** in a pull request, with its **Proposed outcome**. Tag the reviewers named in the ADR.
3. When the deciders approve, set **Status** to the agreed outcome (Accepted, Proposed or Open), remove the "Proposed outcome" line, and update the table above.
4. To change an accepted decision, write a **new** ADR that supersedes it. Mark the old one **Superseded by ADR-NNNN**. Do not rewrite history.

```markdown
# ADR-NNNN: Title

- **Status:** In review | Proposed | Accepted | Open | Superseded by ADR-XXXX
- **Proposed outcome:** (while In review) Accepted | Proposed | Open
- **Date:** DD-MM-YYYY
- **Deciders:** …
- **Related:** PRD §…, FR-…, ADR-…

## Context
## Decision
## Options considered
## Consequences
## Follow-ups
```
