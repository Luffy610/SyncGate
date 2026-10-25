# ADR-0004: One device, two modes — Gate kiosk and Admin — with roles and OS kiosk locking

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Product, Design, Engineering
- **Related:** ADR-0001 · FR-PLT-02, FR-ADM-01..04, FR-ATT-01..06 · NFR-REL-03 · Designs 01–04, 08, 09

## Context

In Phase 1 the **same phone** sits on a stand at the gate all day **and** is the owner's tool for enrolment, corrections, reports and backups ([ADR-0001](0001-phase-1-scope-one-phone-25-workers.md)). We need:

- Workers and guards must not reach admin functions or other apps.
- The owner must get into admin quickly, then back to the gate without forgetting.
- The OS kiosk features differ between Android and iOS and have real limits without MDM.

## Decision

### 1. App modes

The app is always in exactly one mode, owned by `AppModeController`:

| Mode | Who | What is visible | Entry | Exit |
|---|---|---|---|---|
| **Setup** | Owner | Setup wizard only (designs 05–08) | First launch, or after restore | Wizard complete → Gate |
| **Gate** | Workers, guard | Gate screens only (designs 01–04) | Default after setup; app launch; auto-return | Lock button → PIN → Admin |
| **Admin** | Owner, Admin, Gate operator (limited) | Tabs: Today, Workers, Reports, Settings (designs 09–17) | PIN (+ optional OS biometrics) | "Start gate mode", or auto-return |

```
           first launch / restore
                    │
                    ▼
               ┌─────────┐   wizard done   ┌─────────┐   lock + PIN   ┌─────────┐
               │  Setup  │ ──────────────► │  Gate   │ ─────────────► │  Admin  │
               └─────────┘                 └─────────┘ ◄───────────── └─────────┘
                                                ▲       Start gate mode /
                                                │       2 min idle (configurable) /
                                                └───────  app backgrounded & resumed
```

Rules:
- **Auto-return to Gate** after **2 minutes** with no touch in Admin (configurable 1–10 min). Also on app resume after being backgrounded, and on cold start. There is one exception: an enrolment capture in progress holds the timer.
- **The camera pipeline runs only in Gate mode** and during enrolment capture. In Admin it is stopped (saves battery, and avoids marking attendance during admin work).
- While in Admin, a **persistent banner** reads "Gate is paused — workers can't mark attendance" with a one-tap "Back to gate". Any attendance attempted in that window is covered by the guard fallback.

### 2. Roles (FR-ADM-01)

| Capability | Owner | Admin | Gate operator |
|---|---|---|---|
| Exit gate mode | ✓ | ✓ | ✓ (into a limited screen) |
| Guard manual entry | ✓ | ✓ | ✓ |
| Enrol / re-enrol workers | ✓ | ✓ | — |
| Delete worker / erase data | ✓ | — | — |
| Corrections | ✓ | ✓ | — |
| Reports and exports | ✓ | ✓ | — |
| Backup / restore / move phone | ✓ | — | — |
| Licence, roles, PINs | ✓ | — | — |
| Shift rules | ✓ | ✓ | — |

- Each user has a **6-digit PIN**, stored as **Argon2id hash** (memory 19 MiB, t=2) in the encrypted DB. Attempts are rate-limited: 5 tries, then exponential back-off up to 15 minutes. The owner can reset other PINs. The owner's PIN is reset via a recovery code shown once at setup.
- **Optional OS biometric unlock** (`local_auth`: Face ID / Touch ID / Android BiometricPrompt class 3) on top of the PIN, per user. This uses the **OS's** biometrics, not ours, and nothing is stored by us.
- Every mode change and every admin action is written to the audit log ([ADR-0011](0011-data-model-append-only-events.md)).

### 3. Guard fallback (FR-ATT-06), redesigned for ≤25 workers

When a face is not recognised (design 03), the guard taps **"Guard: pick worker from list"**. No PIN is needed for this one action; it is logged as the gate operator.
- The screen (design 04) shows **workers not yet marked for the current direction** (usually ≤10), sorted by name, with search.
- **A reason is required**: Not recognised · Mask / helmet · Injury · Camera issue · New worker not enrolled.
- The event is saved with `method = manual` and appears in the exceptions report.
- Limit: 3 manual entries per worker per day before admin review is needed (prevents abuse).

### 4. OS kiosk locking (FR-PLT-02)

| | Android | iOS |
|---|---|---|
| Phase 1 mechanism | **App pinning** (Screen pinning) started by the app with `Activity.startLockTask()`. Without device-owner status, Android asks the user to confirm. We guide the owner to enable "Ask for PIN before unpinning". | **Guided Access**, enabled by the owner in Settings › Accessibility, started with a triple-click of the side button. |
| What the app can detect | `ActivityManager.getLockTaskModeState()` → show a "Not pinned" warning in Admin and on the gate screen | `UIAccessibility.isGuidedAccessEnabled` + notification → show a "Guided Access is off" warning |
| Can the app start it silently? | Only as **device owner** (MDM / QR provisioning). Not in Phase 1. | Only on **supervised** devices (`UIAccessibility.requestGuidedAccessSession`). Not in Phase 1. |
| After reboot | Pinning ends. The app shows a full-screen "Pin SyncGate again" prompt on first launch after boot. | Guided Access ends. Same prompt. |
| Escape from Admin | Leaving Admin for another app is allowed only for the owner. Pinning is suspended and must be re-pinned to return to gate. | Owner ends Guided Access with the passcode. |

Phase 2 option: **Android Enterprise dedicated-device mode** (device owner via QR provisioning, `setLockTaskPackages`, auto-launch on boot). This is recorded but not built.

### 5. Gate screen behaviour

- Portrait, dark theme, hands-free, no touch needed for a successful mark (NFR-UX-01).
- Confirmation shows for **1.5 s** (green, IN/OUT, name, time, voice). It then returns to scanning. A not-recognised state retries automatically after **3 s**.
- **Cooldown:** a repeat mark within 2 minutes (FR-ATT-05) shows "Already marked IN at 05:52" in neutral grey and is not stored again.
- **Direction** (IN/OUT) comes from the worker's last event and the shift window (FR-ATT-04, [ADR-0012](0012-time-shifts-and-attendance-rules-engine.md)).
- The screen stays on with a wake lock while in Gate mode, and dims when nobody is in view ([ADR-0018](0018-power-thermal-and-reliability-on-a-phone.md)).

## Options considered

| Option | Verdict |
|---|---|
| Separate "gate app" and "admin app" | Rejected: two installs, sharing data needs IPC or sync, and the encrypted store and keys get harder. |
| No kiosk lock, rely on PIN only | Rejected: the phone would be used for WhatsApp, YouTube and calls, and the gate would silently stop. |
| Require Android device-owner provisioning in Phase 1 | Rejected: factory reset + QR provisioning is too much for a self-serve owner. Kept for Phase 2. |
| Keypad worker-ID entry for the guard | Replaced by pick-from-list. With ≤25 workers a list is faster and less error-prone. |

## Consequences

- The owner must re-pin / restart Guided Access after a reboot. The app makes this impossible to miss, but it remains a manual step. NFR-REL-03 ("returns to gate mode without admin action") is **only partly met** in Phase 1 and is noted as a known limitation.
- Admin time is gate downtime. The auto-return timer and banner limit the damage.
