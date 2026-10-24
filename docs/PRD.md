# SyncGate — Smart Attendance Tracker
## Product Requirements Document (PRD)

| Field | Value |
|---|---|
| Document owner | Product Management |
| Status | Draft v0.2 — for review |
| Last updated | 24 Oct 2026 |
| Reviewers | Engineering, ML, Design, Legal/Compliance, Sales |
| Target GA | Before 14 May 2027 (DPDP enforcement date) |

**Change log**

| Version | Change |
|---|---|
| v0.1 | Initial draft: multi-gate sites, LAN sync, contractor channel |
| v0.2 | **v1 scope narrowed to one device per factory.** Primary audience is now **small factory owners**, sold to directly. Multi-device LAN sync, multi-gate, multi-site and the contractor channel moved to [Future Scope](#12-future-scope-v2). Legal questions and numeric targets marked TBD. |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Goals, Non-Goals & Success Metrics](#3-goals-non-goals--success-metrics)
4. [Proposed Solution & Positioning](#4-proposed-solution--positioning)
5. [Target Market & Distribution](#5-target-market--distribution)
6. [Functional Requirements](#6-functional-requirements)
7. [Non-Functional Requirements](#7-non-functional-requirements)
8. [Technical Constraints & Architecture Guidance](#8-technical-constraints--architecture-guidance)
9. [Compliance & Privacy Requirements (DPDP)](#9-compliance--privacy-requirements-dpdp)
10. [Risks & Mitigations](#10-risks--mitigations)
11. [Open Questions & TBDs](#11-open-questions--tbds)
12. [Future Scope (v2+)](#12-future-scope-v2)
13. [Release Plan](#13-release-plan)
14. [Glossary](#14-glossary)

---

## 1. Executive Summary

Small Indian factories that rely on blue-collar and contract labour lose money every day to **attendance fraud** (buddy punching, proxy cards, padded registers) and to **queues at the gate** at shift change. The tools available today force a bad trade-off:

- **Dedicated face-recognition terminals** cost **₹12,000–₹22,000 each** and are single-purpose.
- **Cloud attendance software** charges **per employee per month**, which punishes workforces with high churn and seasonal headcount swings.
- Both typically **send or store biometric data off-site**, which becomes a legal liability once the **Digital Personal Data Protection (DPDP) Act** obligations are enforced from **14 May 2027**, with penalties of **up to ₹250 crore** and a **72-hour breach-reporting** requirement.

**SyncGate v1** turns **one budget Android or iOS tablet (₹8,000–₹10,000)** into a face-recognition attendance terminal for a small factory. All biometric processing happens **on that device**, and face templates never leave it. It works **fully offline**, and the owner exports shift-processed attendance straight to **Excel and Tally** for payroll.

We will sell **directly to small factory owners** with a simple **annual per-device licence** instead of per-employee pricing.

**v1 scope in one line:** *one factory, one device, one gate, fully offline.* Multi-device sync, multiple gates and contractor distribution are deliberately deferred to v2 (see §12).

**Key product bets**

| Bet | Why it matters |
|---|---|
| On-device biometrics | Removes the largest DPDP exposure (cloud biometric stores) and works without internet |
| One commodity tablet | Cheaper than a dedicated terminal, and nothing else to install |
| Per-device annual pricing | Predictable cost that doesn't grow with headcount or churn |
| Owner-first, self-serve setup | A small owner can install and run it without an IT person |
| 200 workers in 10 minutes | Removes the shift-change queue, the most visible pain on the floor |

---

## 2. Problem Statement

### 2.1 Attendance fraud
Manual registers, punch cards and RFID badges are easy to share. Common patterns:
- **Buddy punching:** one worker marks attendance for absent colleagues.
- **Ghost workers:** people on the register who don't exist.
- **Time padding:** late arrivals or early exits recorded as full shifts.

In a small factory these leaks come straight out of the owner's margin, and the resulting disputes take up the owner's own time.

### 2.2 Gate bottlenecks
At shift change, most workers arrive within a 10–15 minute window. Slow terminals or manual registers create queues that delay production, cause workers to skip marking attendance, and lead to arguments about late marks.

### 2.3 Cost of current solutions
| Option | Cost profile | Problems for a small factory |
|---|---|---|
| Dedicated face terminals | ₹12,000–₹22,000 per device | High upfront cost; vendor lock-in; weak reporting; often a separate software licence |
| Cloud attendance SaaS | Per-employee per-month | Cost grows with headcount and churn; needs reliable internet; biometrics held by a third party |
| Manual register / RFID | Low cost | Does not prevent fraud; month-end reconciliation is manual |

### 2.4 Regulatory pressure: DPDP Act
- DPDP obligations become enforceable from **14 May 2027**.
- Face templates are **personal data**. Holding them creates obligations around purpose limitation, security safeguards, retention and erasure.
- Penalties go **up to ₹250 crore** for failures such as inadequate security safeguards.
- Personal data breaches must be reported to the Data Protection Board within **72 hours**.
- Small factory owners have **no compliance function**. Every off-site copy of biometric data is a breach waiting to happen, and they would be liable for it.

> **Problem in one line:** Small Indian factory owners need fraud-proof, fast attendance that runs on one cheap tablet, works without internet, and doesn't turn biometric data into a ₹250-crore liability.

---

## 3. Goals, Non-Goals & Success Metrics

### 3.1 Goals (v1)
1. Eliminate proxy attendance through face verification with liveness checks.
2. Clear **200 workers in ≤10 minutes** on a single device at shift change.
3. Run fully **offline** on one ₹8,000–₹10,000 Android or iOS tablet.
4. Keep biometric data **on the device**, giving the owner a defensible DPDP position.
5. Produce **payroll-ready** output (Excel, Tally) with shift rules applied.
6. Let a small factory owner **set it up and run it themselves** without IT help.

### 3.2 Non-Goals (v1)
- **More than one device per factory**, and any device-to-device sync (LAN or cloud). See §12.
- **Multiple gates or multiple sites** under one account. See §12.
- **Labour-contractor distribution, partner portals and contractor billing.** See §12.
- Full payroll processing, statutory filings (PF/ESI returns) or wage disbursement.
- Cloud-hosted biometric matching or any central face database.
- Access-control hardware (turnstiles, door relays).
- Visitor management, canteen management or GPS field attendance.
- A web admin portal.

### 3.3 Success Metrics

> **TBD:** every number below is a provisional placeholder. Confirm during the feasibility spike (M0) and beta pilots before treating any of them as a commitment.

| Metric | Provisional target (6 months post-GA) |
|---|---|
| Gate throughput | ≥20 workers/min sustained on one device |
| False Accept Rate (FAR) | ≤0.1% (1 in 1,000) |
| False Reject Rate (FRR), normal conditions | ≤2% on first attempt |
| FRR, adverse conditions (low light / mask / dust) | ≤5% on first attempt |
| Self-serve setup completed without support call | ≥80% of new factories |
| Payroll export accepted by Tally without manual edits | ≥95% of exports |
| Paying factories | TBD |
| Licence renewal rate | TBD |
| Biometric data incidents | 0 |

---

## 4. Proposed Solution & Positioning

### 4.1 Positioning statement
> For **small factory owners** who employ blue-collar and contract workers, **SyncGate** is an **offline face-attendance app for one budget tablet** that **stops proxy attendance and gate queues without creating a biometric data liability**. Unlike dedicated terminals or per-employee cloud software, SyncGate **keeps biometrics on the device**, **works without internet**, and costs **one flat annual fee per device, whatever the headcount**.

### 4.2 Product pillars
1. **Privacy-first by architecture.** Capture, template generation and matching all happen on the device. Raw face images are discarded after enrolment. Templates are encrypted at rest and **never leave the device**: not to the cloud, not to backups, not to other devices.
2. **Offline-first.** Every feature works with no network. Internet is needed only for licence check-ins and optional backup of attendance logs.
3. **Built for the factory floor.** Copes with poor lighting, dust, masks, helmets and budget cameras. The UI is fast, glanceable and available in Hindi and regional languages.
4. **Payroll-ready.** Shift rules, overtime and late marks are calculated on the device, with one-tap exports to Excel and Tally.
5. **Owner-friendly.** A guided setup wizard, simple pricing and nothing to install beyond the app.

### 4.3 How it works (high level)
```
 Worker at gate ──► Tablet camera ──► Face detect + liveness ──► On-device template match
                                                                    │
                                     ┌──────────────────────────────┤
                                     ▼                              ▼
                            Attendance event (signed,       Audio/visual confirmation
                            timestamped, no image)          (name, "IN/OUT", time)
                                     │
                     Shift engine ──► Reports ──► Excel / Tally export
                                     │
                     Backup of attendance logs (encrypted, no biometrics)
                     ──► local file and/or owner's Google Drive (optional)
```

---

## 5. Target Market & Distribution

### 5.1 Ideal Customer Profile (ICP), v1
| Attribute | Definition |
|---|---|
| Buyer | **Owner of a small factory**, usually also the decision-maker and often the admin |
| Industry | Textiles & garments, hosiery, auto components, light engineering, food processing |
| Workforce size | **Roughly 50–200 workers** (assumption: one device clearing 200 workers in 10 minutes covers this) |
| Site layout | **One main gate** where attendance is taken |
| Connectivity | Unreliable or no internet at the gate |
| Payroll stack | Excel and/or Tally, often run by the owner or a part-time accountant |
| Geography (launch clusters) | **Surat** (textiles, diamonds), **Tirupur** (knitwear), **Ludhiana** (hosiery, cycle & auto parts), **Pune** (auto components, engineering) |

### 5.2 Personas
| Persona | Role | Needs | Key concern |
|---|---|---|---|
| **Factory Owner** (primary buyer, often admin) | Runs a 50–200 worker unit | Stop wage leakage, end attendance disputes, painless payroll handoff | Cost, ease of use, legal exposure |
| **Supervisor / Accountant** (admin user) | Manages shifts and month-end payroll | Correct shift calculations, quick exports, no manual reconciliation | Accuracy, time spent at month-end |
| **Security Guard / Gate Operator** | Watches over the tablet | Simple UI, quick fixes when recognition fails | Queues, being blamed for errors |
| **Worker** (end user) | Marks attendance daily | Fast, works with mask/helmet, in their own language, fair records | Privacy, wage cuts from wrong marks |

### 5.3 Distribution strategy (v1)
- **Direct to small factory owners** in the launch clusters.
- **Channels:** field sales and demos in industrial areas, local industry associations and trade bodies, local IT/tablet resellers, WhatsApp-led referrals between owners.
- **Self-serve onboarding:** recommended tablet list, stand/mount guide, Hindi and regional-language setup videos, and a 30-day free trial on one device.
- Labour-contractor distribution is a v2 channel (§12).

### 5.4 Pricing model
- **Annual licence per device.** In v1 that means one licence per factory, with no limit on workers.
- Price point **TBD** (decision D-3).
- Constraint: **3-year cost (tablet + licence) must stay well below a dedicated terminal plus its software.**

---

## 6. Functional Requirements

Priority key: **P0** = required for GA, **P1** = required within 3 months of GA, **P2** = future/backlog.

### 6.1 Platform & Device
| ID | Requirement | Priority |
|---|---|---|
| FR-PLT-01 | The app shall run natively on **Android** (min. Android 9 / API 28) and **iOS / iPadOS** (min. iOS 15), with all P0 features available on both. | P0 |
| FR-PLT-02 | The app shall support **kiosk / single-app mode** (Android Lock Task / Screen Pinning, iOS Guided Access) so the gate device can't be used for anything else. | P0 |
| FR-PLT-03 | The app shall support phones and tablets in portrait and landscape, with the layout tuned for an 8–10" tablet on a stand. | P0 |
| FR-PLT-04 | The app shall detect unsupported hardware (camera resolution, RAM, CPU) during setup and warn about it. | P1 |
| FR-PLT-05 | v1 shall support **exactly one active device per factory licence**. | P0 |

### 6.2 Worker Enrolment
| ID | Requirement | Priority |
|---|---|---|
| FR-ENR-01 | An admin shall enrol a worker with guided multi-angle face capture plus these fields: name, worker ID, department, designation, shift group, contractor name (optional), phone (optional). | P0 |
| FR-ENR-02 | The system shall record **informed notice / consent** (or the applicable legal basis; see TBD-L1) at enrolment, in the worker's chosen language, with a timestamp and the enrolling admin's ID. | P0 |
| FR-ENR-03 | The system shall support optional **masked-face enrolment** (an extra sample with a mask) to improve recognition of masked faces. | P0 |
| FR-ENR-04 | The system shall reject poor captures (blur, occlusion, extreme pose, low light) and tell the admin how to fix them. | P0 |
| FR-ENR-05 | The system shall detect **duplicate enrolment** (the same face under a different worker ID) and flag it for admin review. | P0 |
| FR-ENR-06 | The system shall support bulk import of worker details from CSV/Excel, with faces captured later on the device. | P1 |
| FR-ENR-07 | Admins shall be able to deactivate, re-enrol or permanently delete a worker. Deleting a worker shall erase their template from the device. | P0 |

### 6.3 Attendance Capture (Gate Mode)
| ID | Requirement | Priority |
|---|---|---|
| FR-ATT-01 | The app shall continuously detect faces in the camera frame and mark attendance **hands-free**, with no button press. | P0 |
| FR-ATT-02 | The system shall run **passive liveness detection** that rejects photos, screens and video replays. | P0 |
| FR-ATT-03 | On a match, the app shall show clear visual and audio confirmation (worker name, IN/OUT, time) in under 1 second. | P0 |
| FR-ATT-04 | The system shall work out IN or OUT from the worker's last event and the shift schedule. The single gate is bidirectional by default. | P0 |
| FR-ATT-05 | The system shall ignore repeat marks within a configurable cooldown window (default 2 minutes). | P0 |
| FR-ATT-06 | When there is no match or only a low-confidence match, the app shall offer a **fallback**: retry, or a guard-assisted manual entry by worker ID with a mandatory reason. Every manual entry shall be flagged in reports. | P0 |
| FR-ATT-07 | Each attendance event shall store: event UUID, worker ID, device ID, timestamp, direction, match confidence, liveness score and method (face/manual). **No face image shall be stored** by default. | P0 |
| FR-ATT-08 | Optionally (off by default, needing explicit admin opt-in and notice to workers), the system may keep a low-resolution **evidence thumbnail** for disputed or manual entries. Thumbnails are auto-deleted after a configurable period (max 90 days). | P2 |

### 6.4 Offline Operation, Backup & Device Replacement
| ID | Requirement | Priority |
|---|---|---|
| FR-OFF-01 | The device shall work fully on its own with no network. All P0 features shall be available offline. | P0 |
| FR-OFF-02 | Because v1 has one device, **attendance data must be backed up**. The app shall create **encrypted backups of attendance logs, worker details (without biometrics), shift rules and settings**, either as a local file (shareable via USB, WhatsApp or email) or automatically to the owner's own **Google Drive** when online. | P0 |
| FR-OFF-03 | Backups shall **never contain biometric templates**. | P0 |
| FR-OFF-04 | The app shall remind the admin when no backup has been taken for a configurable period (default 7 days). | P0 |
| FR-OFF-05 | **Device replacement:** a new device can restore from a backup and take over the licence. Since templates are not backed up, workers re-enrol their faces on the new device. Worker details and attendance history are kept. | P0 |
| FR-OFF-06 | **Clock integrity:** the app shall detect manual changes to the device clock (e.g. using a monotonic counter and the last known network time), flag affected events and alert the admin. | P0 |

### 6.5 Shift & Attendance Rules (Admin)
| ID | Requirement | Priority |
|---|---|---|
| FR-SHF-01 | Admins shall define shifts with start and end times, including **night shifts that cross midnight**. | P0 |
| FR-SHF-02 | Admins shall configure grace periods, late-mark and early-exit thresholds, half-day rules, minimum hours for a full day, and break deductions. | P0 |
| FR-SHF-03 | The system shall calculate **overtime** with configurable rules (daily threshold, weekly threshold, OT multiplier labels). | P0 |
| FR-SHF-04 | The system shall support **rotating shifts**, assigning workers to shift groups, and per-day overrides. | P1 |
| FR-SHF-05 | The system shall support weekly offs, holiday calendars (national, state and factory-specific) and leave marking. | P1 |
| FR-SHF-06 | The system shall handle missing punches (IN without OUT) with configurable auto-close rules and flag them for review. | P0 |
| FR-SHF-07 | Admins shall be able to correct attendance records with a mandatory reason. Every change shall be **audit-logged** (who, when, before and after). | P0 |

### 6.6 Reports & Payroll Export
| ID | Requirement | Priority |
|---|---|---|
| FR-RPT-01 | The app shall show live daily views: present, absent, late arrivals and currently on premises, filterable by department and shift. | P0 |
| FR-RPT-02 | The app shall generate a monthly **muster roll / attendance register**, filterable by department, shift and contractor name. | P0 |
| FR-RPT-03 | The system shall export to **Excel (.xlsx)** using configurable column templates. | P0 |
| FR-RPT-04 | The system shall export in a **Tally-importable format** (Tally Prime XML for payroll attendance / production types), mapping worker IDs to Tally employee masters. | P0 |
| FR-RPT-05 | Exports shall be shareable through the OS share sheet (WhatsApp, email, USB, Drive) and saveable to local storage. | P0 |
| FR-RPT-06 | The system shall provide an exceptions report covering manual entries, low-confidence matches, missing punches, duplicate-enrolment flags and clock-change flags. | P0 |
| FR-RPT-07 | Statutory register formats (as required under applicable labour codes and state rules). | P2 |

### 6.7 Localization & Accessibility
| ID | Requirement | Priority |
|---|---|---|
| FR-L10N-01 | The UI shall be available in **English and Hindi** at GA. | P0 |
| FR-L10N-02 | The UI shall support the regional languages of the launch clusters: **Gujarati** (Surat), **Tamil** (Tirupur), **Punjabi** (Ludhiana), **Marathi** (Pune). | P0 for each cluster's language at that cluster's launch; P1 overall |
| FR-L10N-03 | Gate-mode confirmations shall use **voice prompts** in the selected language plus icons and colours, so they work for workers who can't read well. | P0 |
| FR-L10N-04 | Language shall be settable for the device and for each admin user. Worker notices shall be shown in the worker's chosen language. | P0 |
| FR-L10N-05 | Dates, numbers and times shall follow Indian conventions (DD-MM-YYYY, Indian digit grouping, 12/24-hour toggle). | P0 |
| FR-L10N-06 | All strings shall be externalised so new languages can be added without code changes. | P0 |

### 6.8 Licensing
| ID | Requirement | Priority |
|---|---|---|
| FR-LIC-01 | The app shall be activated with a **server-issued licence key** tied to one factory and one device. | P0 |
| FR-LIC-02 | Licences shall be **annual and per device**, with no limit on enrolled workers. | P0 |
| FR-LIC-03 | Licences shall use **cryptographically signed tokens** that can be verified offline. The device shall check in with the licence server periodically, with a grace period before features are restricted. (Check-in interval and grace period: TBD.) | P0 |
| FR-LIC-04 | When a licence expires, **attendance capture shall keep working through the grace period**, and **data export shall never be blocked**. Workers' wages must never depend on a licence renewal. | P0 |
| FR-LIC-05 | The licence server shall receive **only licence metadata**: licence ID, device ID, app version, last-seen timestamp and aggregate counts. No personal or biometric data. | P0 |
| FR-LIC-06 | Device transfer: the licence can move to a replacement device, which deactivates the old one (see FR-OFF-05). | P0 |
| FR-LIC-07 | In-app renewal and payment via UPI or a payment link. | P1 |

### 6.9 Admin, Roles & Security Features
| ID | Requirement | Priority |
|---|---|---|
| FR-ADM-01 | Role-based access with **Owner**, **Admin (supervisor/accountant)** and **Gate Operator (guard)** roles. Gate operators cannot view reports or export data. | P0 |
| FR-ADM-02 | Admin functions shall require a PIN or password, with optional device biometric (OS-level) authentication. | P0 |
| FR-ADM-03 | All admin actions (enrolment, deletion, edits, exports, settings changes) shall be written to a tamper-evident **audit log**. | P0 |
| FR-ADM-04 | A **guided setup wizard** shall cover licence activation, language, first shift, camera and lighting check, and the first worker enrolment. | P0 |

### 6.10 Data Principal (Worker) Rights
| ID | Requirement | Priority |
|---|---|---|
| FR-DPR-01 | Admins shall be able to produce a summary of the personal data held about a worker (attendance history and details) when the worker asks. | P0 |
| FR-DPR-02 | The system shall support worker requests for **correction** and **erasure** (subject to legal retention rules for wage records; TBD-L3), logged with timestamps. | P0 |
| FR-DPR-03 | Templates of workers inactive for longer than a configurable period (default 90 days after exit) shall be **auto-deleted**. | P0 |
| FR-DPR-04 | The app shall show the grievance contact and privacy notice in the worker's language. | P0 |

---

## 7. Non-Functional Requirements

> Numeric targets in this section are provisional (**TBD**, see §3.3) until validated in M0 and the beta pilots.

### 7.1 Performance & Throughput
| ID | Requirement |
|---|---|
| NFR-PERF-01 | **One device shall clear 200 workers in ≤10 minutes**: a sustained ≥20 workers/min, or ≤3 s per worker from walk-up through recognition to confirmation. |
| NFR-PERF-02 | Face detection, liveness and matching together shall take **≤700 ms at p95** on the reference budget device, with 500 enrolled workers. |
| NFR-PERF-03 | Matching shall support up to **1,000 enrolled templates** per device with no more than a 20% latency increase. |
| NFR-PERF-04 | A cold start into gate mode shall take ≤5 s on the reference device. |
| NFR-PERF-05 | A monthly Excel/Tally export for 200 workers shall finish in ≤15 s on the device. |

### 7.2 Recognition Accuracy & Environmental Resilience
| ID | Requirement |
|---|---|
| NFR-ACC-01 | FAR ≤0.1% and FRR ≤2% (first attempt) under normal indoor lighting (≥150 lux). |
| NFR-ACC-02 | **Low light:** FRR ≤5% down to about 30 lux, using frame enhancement and an on-screen fill light (white screen flash) where needed. |
| NFR-ACC-03 | **Backlight / outdoor gates:** recognition shall work with a strong backlight (gate facing outdoors), helped by exposure guidance during setup. |
| NFR-ACC-04 | **Masks:** FRR ≤5% for workers wearing surgical or cloth masks, without removing them, while FAR stays ≤0.1%. |
| NFR-ACC-05 | **Dust & grime:** when image quality drops below a threshold because of a dirty lens, the app shall prompt the operator to clean the camera. |
| NFR-ACC-06 | **Headgear & PPE:** recognition shall cope with safety helmets, caps, head scarves, turbans, bindis/tilak and clear safety glasses. |
| NFR-ACC-07 | **Demographic fairness:** accuracy shall be validated across skin tones, genders and age groups typical of Indian industrial workforces. No group's FRR may exceed 1.5× the overall FRR. |
| NFR-ACC-08 | **Liveness:** must reject printed photos, phone/tablet screen replays and video replays, with an attack acceptance rate ≤2% (tested along the lines of ISO/IEC 30107-3). |

### 7.3 Hardware Envelope
| ID | Requirement |
|---|---|
| NFR-HW-01 | **Reference device class:** ₹8,000–₹10,000 Android tablets with roughly 3–4 GB RAM, an entry-level octa-core chip, a 5 MP+ front camera and Android 11+. At least two named reference models shall be certified before GA. |
| NFR-HW-02 | On iOS, the lowest supported device is the base iPad model that runs iOS 15+. This is above the budget band but needed for cross-platform support. |
| NFR-HW-03 | App install size ≤80 MB. One year of attendance for 200 workers shall use ≤100 MB of device storage. |
| NFR-HW-04 | The app shall run **continuously for 12+ hours on mains power** without overheating slowing throughput below NFR-PERF-01, and run ≥4 hours on battery during a power cut. |

### 7.4 Reliability & Availability
| ID | Requirement |
|---|---|
| NFR-REL-01 | Gate mode shall be available ≥99.5% of configured shift time, excluding hardware or power failure. |
| NFR-REL-02 | **Zero data loss on the device:** each attendance event is written to durable local storage (a transactional database with write-ahead logging) before the confirmation is shown. |
| NFR-REL-03 | The app shall recover automatically after crashes, power loss and OS restarts, returning to gate mode without admin action. |
| NFR-REL-04 | As the single device is a single point of failure, the guard shall have a **documented fallback** (paper register, entered later as flagged manual entries) for when the device is down. |

### 7.5 Security
| ID | Requirement |
|---|---|
| NFR-SEC-01 | Biometric templates and the local database shall be **encrypted at rest** (AES-256), with keys held in hardware-backed storage (Android Keystore; iOS Keychain + Secure Enclave where available). |
| NFR-SEC-02 | Templates shall be stored in a **non-reversible, model-specific form**. Raw enrolment images are discarded once the template is created. |
| NFR-SEC-03 | All network traffic (licence server, Drive backup) shall use TLS 1.2+ (TLS 1.3 preferred), with certificate pinning for the licence server. |
| NFR-SEC-04 | Backups shall be encrypted on the device with a key the vendor never holds. |
| NFR-SEC-05 | The app shall detect rooted or jailbroken devices and tampered app binaries, and restrict biometric functions on them. |
| NFR-SEC-06 | An independent penetration test and a biometric privacy review shall be completed before GA. |

### 7.6 Usability
| ID | Requirement |
|---|---|
| NFR-UX-01 | Workers shall need **no training** beyond "look at the screen". Getting from walk-up to confirmation shall need no touch. |
| NFR-UX-02 | A factory owner shall be able to complete setup (licence activation, first shift, first enrolment) in ≤30 minutes using the wizard, with no support call. |
| NFR-UX-03 | Enrolling one worker shall take ≤60 s. |
| NFR-UX-04 | Gate-mode text shall be readable from 1.5 m away, touch targets shall be ≥48 dp, and success/retry shall use high-contrast colours (green/red) backed by icons for colour-blind users. |

### 7.7 Maintainability & Operability
| ID | Requirement |
|---|---|
| NFR-OPS-01 | App updates shall be distributed via the Play Store and App Store, plus a sideload APK for Android. |
| NFR-OPS-02 | ML models shall be versioned. A model upgrade that changes the template format shall come with an on-device migration or re-enrolment path. |
| NFR-OPS-03 | Crash reports and diagnostics shall be opt-in and **stripped of personal and biometric data**. |
| NFR-OPS-04 | The owner shall be able to export a diagnostic bundle (logs and device info, no personal data) to send to support. |

---

## 8. Technical Constraints & Architecture Guidance

### 8.1 Hard constraints
| # | Constraint | Implication |
|---|---|---|
| TC-01 | **Biometrics never leave the device:** not to the cloud, backups, telemetry or any other device. | No server-side matching. No biometric fields in any API, backup or telemetry schema, enforced by schema review and automated tests. |
| TC-02 | **Must run on ₹8,000–₹10,000 hardware.** | Models must be quantised (INT8) and optimised for mobile, with the whole ML pipeline ≤25 MB. No reliance on neural accelerators that budget chips lack: GPU/NNAPI acceleration is optional and a CPU fallback is mandatory. |
| TC-03 | **Full iOS and Android support.** | A cross-platform UI framework (e.g. Flutter or React Native) with native modules for camera and ML inference. The ML runtime must work on both platforms (e.g. TensorFlow Lite / LiteRT, or ONNX Runtime Mobile; Core ML optional on iOS). |
| TC-04 | **No internet dependency for core features.** | Local-first data model; licence verification via signed offline tokens; no cloud authentication anywhere on the gate path. |
| TC-05 | **One device per factory in v1.** | No sync layer in v1. The data model should still use UUIDs and append-only attendance events so v2 multi-device sync can be added without a migration (see §12). |
| TC-06 | **Tally integration is file-based.** | Generate Tally Prime-compatible XML for import; never depend on Tally's ODBC/HTTP server being reachable. |
| TC-07 | **App store policies.** | Kiosk use, camera permissions and biometric data handling must comply with Google Play and Apple App Store policies, including the Data Safety section and privacy nutrition labels. |

### 8.2 Recommended reference architecture (v1)
```
┌──────────────────────────── Gate Device (Android / iOS) ────────────────────────────┐
│  UI layer (cross-platform)  ── Gate Mode │ Admin │ Enrolment │ Reports │ Settings    │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│  Vision pipeline (native):  Camera ► Face detect ► Quality gate ► Liveness ►        │
│                             Alignment ► Embedding model ► 1:N matcher (in-memory)   │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│  Domain:  Attendance event log (append-only, UUIDs) │ Shift engine │ Export engine  │
│  Storage: Encrypted SQLite (SQLCipher)  +  Template vault (Keystore/Keychain keys)  │
│  Backup:  Encrypted export (no templates) ► local file / Google Drive               │
│  Licence: Signed token verifier ► periodic check-in client                          │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                   │ Internet (optional, intermittent)
                                   ▼
               Licence server (metadata only) · Owner's Google Drive (encrypted, no biometrics)
```

### 8.3 ML pipeline guidance
- **Detection:** a lightweight detector (BlazeFace / SCRFD class) at reduced input resolution for speed.
- **Recognition:** a compact embedding model (MobileFaceNet / ArcFace-loss class), INT8-quantised, fine-tuned or validated on South Asian faces and masked-face data.
- **Masked faces:** a mask-aware model or a periocular-weighted embedding, plus optional masked enrolment samples (FR-ENR-03).
- **Liveness:** a passive single- or multi-frame model using texture and depth cues. No active challenges in gate mode, because they would slow throughput.
- **Matching:** in-memory 1:N cosine-similarity search. Thresholds are configurable within vendor-defined safe bounds.
- **Model and dataset licences:** every model and training dataset must permit **commercial use**. Legal verification is TBD (TBD-L2).

### 8.4 External dependencies
| Dependency | Purpose | Constraint |
|---|---|---|
| Licence server (vendor-hosted, India region) | Licence issuance and check-in | Must hold no personal or biometric data |
| Google Drive API | Optional backup | Owner's own account; encrypted on the device first |
| Play Store / App Store | Distribution | Policy compliance; sideload APK as a fallback on Android |

---

## 9. Compliance & Privacy Requirements (DPDP)

> **TBD (legal review pending):** this section lists product requirements, not legal advice. The open legal questions are listed in §11 and are parked for now. Everything here must be checked by legal counsel against the DPDP Act, 2023 and the notified DPDP Rules before GA.

### 9.1 Roles
- The **factory owner** is the **Data Fiduciary** for worker data.
- **SyncGate (the vendor)** is designed to **not process worker personal data at all**: it has no access to biometrics or attendance records. This keeps the vendor's obligations to a minimum and is a key sales message.

### 9.2 Product requirements derived from DPDP
| ID | Requirement | DPDP principle |
|---|---|---|
| CMP-01 | A worker-facing **notice** at enrolment (itemised data collected, purpose, rights, grievance contact) in the worker's language. | Notice & consent / legitimate use |
| CMP-02 | Record the **legal basis** for each worker (consent, or employment-related legitimate use; TBD-L1) with a timestamp. | Lawful processing |
| CMP-03 | **Purpose limitation:** templates are used only to verify attendance, and no other feature may read them. | Purpose limitation |
| CMP-04 | **Data minimisation:** no raw images are kept, and event records contain no images by default. | Data minimisation |
| CMP-05 | **Retention and erasure:** configurable retention for attendance records (aligned with wage-record retention law; TBD-L3) and auto-deletion of templates after a worker leaves (FR-DPR-03). | Storage limitation |
| CMP-06 | **Security safeguards:** encryption at rest and in transit, access control and audit logs (NFR-SEC-*). | Reasonable security safeguards |
| CMP-07 | **Breach-readiness toolkit:** an in-app incident record (lost or stolen device report), remote licence revoke with a local data wipe at next check-in, and a pre-filled breach notification template, so the owner can meet the **72-hour** reporting window. | Breach notification |
| CMP-08 | Workflows for **worker rights**: access, correction, erasure and grievance (FR-DPR-*). | Rights of data principals |
| CMP-09 | Give owners a simple **DPDP compliance pack**: a one-page data-flow diagram, a data inventory, a security summary, and template notice/consent text in the supported languages. | Accountability (customer enablement) |
| CMP-10 | **Children's data:** capture date of birth at enrolment, block enrolment of anyone under 18 and alert the admin. | Children's data / labour law |

### 9.3 Lost or stolen device scenario
With a single device, losing the tablet means losing access to unbacked-up data **and** a potential breach. Requirements:
1. Data on the device can't be read without its hardware-bound keys (NFR-SEC-01).
2. The owner can report the device lost (via support or the licence account). The licence is revoked, and if the device ever comes online it receives a wipe command.
3. The incident is recorded with a timestamp for the owner's breach assessment (CMP-07).
4. The owner restores the data on a new device from the latest backup (FR-OFF-05).

---

## 10. Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | A budget device can't reach 20 workers/min with liveness on | Medium | High | Early benchmarking on reference models (M0); model quantisation; certified device list |
| R-2 | Accuracy with masks or in low light falls short of target | Medium | High | Masked enrolment samples; mask-aware model; lighting check during setup; recommend a low-cost LED light accessory |
| R-3 | Spoofing (photo or screen) undermines the anti-fraud promise | Medium | High | Passive liveness; ISO 30107-3-style testing; exceptions report |
| R-4 | The single device is a single point of failure (breakage, theft, power) | Medium | High | Backup reminders, quick restore, paper fallback process, lockable stand; multi-device in v2 |
| R-5 | Small owners are price-sensitive or slow to adopt new tech | High | Medium | Free trial; flat pricing; regional-language demos; ROI calculator on wage leakage |
| R-6 | Factories larger than one device can serve sign up and hit throughput limits | Medium | Medium | Qualify by headcount at sale; position v2 multi-device for them |
| R-7 | Legal reading of DPDP changes product requirements | Medium | High | Parked as TBD; design for the stricter reading in the meantime |
| R-8 | Model or dataset licences restrict commercial use | Medium | High | Parked as TBD-L2; must be resolved before GA |
| R-9 | iOS platform limits (kiosk, camera background behaviour) | Medium | Low–Med | Guided Access; Android positioned as the main gate platform |
| R-10 | Licence piracy through APK tampering | Medium | Medium | Signed tokens; integrity checks (Play Integrity / App Attest); server-side device binding |

---

## 11. Open Questions & TBDs

### 11.1 Decisions
| ID | Question | Status |
|---|---|---|
| D-1 | ~~Sharing templates across gates and devices~~ | **Resolved (v0.2):** v1 is one device per factory, so templates never leave the device. Revisit for v2. |
| D-2 | Cross-platform framework: Flutter vs React Native vs Kotlin Multiplatform, judged on camera and ML performance on budget Android. | TBD |
| D-3 | Pricing: annual price point per device, trial terms. | TBD |
| D-4 | Should evidence thumbnails (FR-ATT-08) ever be offered, given the privacy positioning? | TBD (post-GA) |
| D-5 | Which Tally versions/editions to support (Tally Prime only, or also Tally ERP 9)? | TBD |

### 11.2 Legal TBDs (parked)
| ID | Question | Status |
|---|---|---|
| TBD-L1 | Legal basis for biometric processing of workers under DPDP: consent, or legitimate use for employment? | TBD |
| TBD-L2 | Do the face-recognition models and training datasets permit commercial use? | TBD |
| TBD-L3 | Wage-record retention periods by state, to set default retention values. | TBD |

### 11.3 Numeric targets (parked)
All success metrics (§3.3), NFR thresholds (§7), licence check-in/grace periods (FR-LIC-03) and release dates (§13) are **provisional placeholders**. Confirm them in M0 and the beta pilots.

---

## 12. Future Scope (v2+)

Deliberately out of v1, kept here so v1 design choices don't block them:

| Item | Notes |
|---|---|
| **Multiple devices per factory** | Peer-to-peer sync over the factory LAN without internet (mDNS discovery, mutually authenticated TLS, append-only event replication with UUID de-duplication and hybrid logical clocks). Needs the template-sharing decision (old D-1) revisited with legal. |
| **Multiple gates** | IN-only, OUT-only and bidirectional gate types; per-gate reports; detecting the same worker at two gates within seconds. |
| **Larger factories (200–500+ workers)** | Several devices per gate to keep the 10-minute shift-change target. |
| **Labour-contractor channel** | Contractor accounts managing many factories, a partner portal for issuing and transferring licences, contractor billing summaries (man-days, OT), partner margins. |
| **Multi-site accounts** | One owner or contractor managing several factories with separate data per site. |
| **Per-gate pricing tiers** | Starter / Site / Contractor licence bundles. |

---

## 13. Release Plan

> Dates are indicative (**TBD**).

| Milestone | Timeline | Scope / Exit criteria |
|---|---|---|
| **M0: Feasibility spike** | Nov–Dec 2026 | ML pipeline benchmarked on 2 reference budget tablets; ≥20 workers/min proven on one device; framework decision (D-2) |
| **M1: Alpha** | Jan–Feb 2027 | Enrolment, gate mode, liveness, shifts, Excel export, Hindi; internal use plus 1 friendly factory |
| **M2: Closed beta** | Mar–Apr 2027 | Tally export, licensing, backup and restore, regional language for the pilot cluster, DPDP compliance pack; 5–10 small factories in Surat and Tirupur |
| **M3: GA** | By 1 May 2027 (ahead of DPDP enforcement on 14 May 2027) | All P0 requirements met; penetration test passed; certified device list published; Ludhiana and Pune launch |
| **M4: Post-GA** | Jun–Aug 2027 | P1 features: rotating shifts, holiday calendars, bulk import, in-app renewal |
| **v2 planning** | From Q3 2027 | Multi-device sync, multiple gates and contractor channel (§12) |

**GA launch criteria:** all P0 functional requirements complete; NFR-PERF-01 and NFR-ACC-01 to 04 verified on certified devices in real factory conditions; no open Sev-1 or Sev-2 security findings; legal TBDs (§11.2) closed.

---

## 14. Glossary

| Term | Definition |
|---|---|
| **DPDP Act** | Digital Personal Data Protection Act, 2023 (India), and its Rules |
| **Data Fiduciary** | The entity that decides the purpose and means of processing personal data (here, the factory owner) |
| **Data Principal** | The person the data is about (here, the worker) |
| **FAR / FRR** | False Accept Rate / False Reject Rate of face recognition |
| **Liveness detection** | Checking that a real, live person is in front of the camera, not a photo or video |
| **Template / Embedding** | A numerical representation of a face used for matching; not a photo |
| **Muster roll** | Statutory register of workers' attendance |
| **Kiosk mode** | OS feature that locks a device to a single app |
