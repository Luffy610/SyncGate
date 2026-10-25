# ADR-0018: Duty-cycled camera, wake/thermal management, crash recovery and a paper fallback

- **Status:** In review
- **Proposed outcome:** Accepted (numbers validated in the M0 soak test)
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product
- **Related:** NFR-HW-04, NFR-PERF-04, NFR-REL-01..04 · Risk R-4 · ADR-0001, ADR-0004, ADR-0006

## Context

A phone running its camera, screen and ML all day gets **hot** and drains its battery. Budget phones throttle aggressively, and the OS kills or restricts apps it thinks are misbehaving. With ≤25 workers, the gate is **idle more than 95% of the day**: activity clusters around shift starts and ends.

## Decision

### 1. Gate pipeline duty cycle

| State | Trigger | Camera | Analysis | Screen |
|---|---|---|---|---|
| **Active** | Face detected within the last 10 s | 640×480 @ 15 fps | Full pipeline on candidate frames | 100% (or fill-light white in low light) |
| **Watching** | No face for 10 s | 320×240 @ 5 fps | Detection only | 60% |
| **Idle** | No face for 60 s | 320×240 @ 2 fps | Detection only | 20%, dark "Look at the screen" screen; clock visible |
| **Peak window** | ±20 min around configured shift start/end | Never drops below *Watching* | — | ≥60% |

- Wake-up from Idle → Active takes ≤300 ms (one detection frame + camera reconfigure). The worker sees the screen brighten as they approach.
- Screen stays on with a wake lock (`wakelock_plus`, Android `FLAG_KEEP_SCREEN_ON`, iOS `isIdleTimerDisabled`) **only in Gate mode**.

### 2. Thermal management

- Monitor **Android** `PowerManager.getCurrentThermalStatus()` / `addThermalStatusListener` (API 29+) and **iOS** `ProcessInfo.thermalState`.
- At `MODERATE`/`.serious`: cap analysis at 8 fps, prefer the CPU delegate with 2 threads, dim the screen 20%.
- At `SEVERE`/`.critical`: Watching-mode limits even with a face present; show the owner a "Phone is too hot — move out of the sun" warning. Attendance still works, more slowly.
- The setup guide recommends mounting out of direct sunlight, using a stand that does not cover the back, and avoiding thick cases.

### 3. Power

- **The phone is expected to be on the charger** in Gate mode. The app warns when unplugged in Gate mode for more than 10 minutes, with remaining runtime estimated from battery drain.
- Target: **≥4 h on battery** in Gate mode during a power cut, using the duty cycle (NFR-HW-04).
- Battery health: the setup guide shows how to turn on the OS **charge limit / battery protection** (80% cap) where available (many Android OEMs; iOS "Optimised Battery Charging").
- Android: request exemption from battery optimisation (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) with a clear explanation. Show OEM-specific guidance (Xiaomi, Oppo, Vivo, Realme, Samsung) from a bundled "don't kill my app" table, so background backup work is not killed.

### 4. Crash and restart recovery (NFR-REL-03)

| Event | Behaviour |
|---|---|
| App crash in Gate mode | Android: an `UncaughtExceptionHandler` schedules a relaunch via `AlarmManager` (allowed while app pinning is active, verify in M0); iOS: Guided Access keeps the app frontmost and it relaunches into Gate. On relaunch → integrity check → Gate mode in ≤5 s (NFR-PERF-04). |
| OS kills app in background | On next launch, the app always opens in Gate mode. |
| Phone reboot | The app cannot auto-start without MDM (Android 10+ background activity limits; iOS). A full-screen "Open SyncGate and pin it" prompt is the owner's job. We add an Android `BOOT_COMPLETED` receiver that posts a high-priority notification "Tap to start SyncGate gate". |
| Power loss mid-write | SQLite WAL + `synchronous=FULL` → no committed event lost; the gate only confirms after commit ([ADR-0010](0010-local-storage-and-encryption.md)). |

### 5. Paper fallback (NFR-REL-04)

- The app includes a printable **paper register** template (name list for the next 7 days, with IN/OUT columns and guard signature) under Settings › Help.
- After an outage, the owner enters paper records through **"Add from paper register"**. This bulk manual entry needs a reason ("Device down"), is flagged, and is visible in exceptions.

### 6. Availability target

- Gate available **≥99.5% of configured shift time** (NFR-REL-01), excluding hardware and power failure. This is measured on-device (gate-mode uptime vs shift schedule) and included in the diagnostic bundle.

## Options considered

| Option | Verdict |
|---|---|
| Camera always at full rate | Rejected: heat and battery. |
| Motion sensor / proximity to wake | Proximity sensors on phones face the wrong way and have tiny range; low-fps face detection works better. |
| Background foreground-service camera | Not needed: the app is always foreground in Gate mode. |

## Consequences

- The M0 **12-hour soak test** on each reference phone (plugged in, 30 °C room) and a **4-hour battery test** are release gates.
- Owners must accept one manual step after reboots in Phase 1 ([ADR-0004](0004-single-device-gate-and-admin-modes.md)).
