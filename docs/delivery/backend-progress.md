# SyncGate: back end and integration progress

Live tracker for the Spring Boot back end, the Dart API client and the Android integration work. It answers three
questions: **what is done, which branch/PR holds it, what is next.** Update it in the same PR as the work.

| | |
|---|---|
| Last updated | 12-11-2026 |
| Default branch | `master` (there is no `main` branch in this repository) |
| Plan it follows | [phase-1-delivery-plan.md](phase-1-delivery-plan.md) (F6/F7 of the [frontend plan](frontend-implementation-plan.md)) |
| How it all fits together | [docs/backend/README.md](../backend/README.md) |

## 1. Where we are, by layer

| Layer | State | Evidence |
|---|---|---|
| Flutter screens (every Phase 1 screen, iOS + Android looks, en + hi) | ✅ Done | 242 app tests |
| Spring Boot API: auth, workers, shifts, settings, attendance, corrections, exceptions, reports, Excel/CSV/Tally export, backup/restore, licence | ✅ Done | 58 server tests |
| Database: schema v1 to v4 (Flyway), append-only tables, SHA-256 hash chains, tamper checks | ✅ Done on H2; ⚠️ Postgres-only trigger migration (`V2`) never run on a real PostgreSQL | tamper tests, live runs |
| Dart API client (`sg_api`) and wiring (`main_dev_api.dart`) | ✅ Done | 27 client tests + live test against the running server |
| Real Android services (share sheet, voice, biometrics, keep-awake, screen pinning, hardware check, file picker) | ✅ Done | share sheet verified on the emulator; the rest unit-checked |
| Restore from backup (API + screen) | ✅ Done | server + widget tests |
| Full-stack test on a device (real UI, real API, real database) | ✅ Passing on an Android emulator | `integration_test/real_stack_test.dart`, `tools/test-real-stack.ps1` |
| Face recognition (camera, detection, liveness, matching, template vault) | ⏳ Not started here (written separately; seam is `FaceRecognitionPort`) | see docs/backend/README.md |
| Google Drive backup client | ⏳ Not built (local folder stands in) | |
| Licence server as a separate Go service (ADR-0014) | ⏳ Not built (mock inside the Spring app) | |
| HTTPS/certificate pinning, per-phone device keys, penetration test | ⏳ Not done | security section of docs/backend/README.md |
| iOS native work, iOS flavour schemes | ⏳ Needs a Mac | |

## 2. Step log

Each step is one branch with feature-scoped commits. Every step ended with the tests of that point green.

| # | Step | Branch | Merged order | Done | Tests after the step |
|---|---|---|---|---|---|
| 1 | Spring Boot scaffold, typed config, startup guard, schema v1, hash-chain service, error model | [`feature/backend-api-scaffold`](https://github.com/Luffy610/SyncGate/pull/3) (PR #3) | 1 | 28-10-2026 | builds |
| 2 | PIN login (Argon2id), device token, recovery code, lockout, audit chain, security config | [`feature/backend-auth-security`](https://github.com/Luffy610/SyncGate/pull/4) (PR #4) | 2 | 28-10-2026 | 9 server |
| 3 | Workers, consents, shifts, settings | [`feature/backend-workers-shifts-settings`](https://github.com/Luffy610/SyncGate/pull/5) (PR #5) | 3 | 28-10-2026 | 14 server |
| 4 | Attendance events, manual marks, corrections, exceptions, face-recognition seam (mock) | [`feature/backend-attendance-exceptions`](https://github.com/Luffy610/SyncGate/pull/6) (PR #6) | 4 | 28-10-2026 | 23 server |
| 5 | Monthly muster, daily view, Excel and CSV export | [`feature/backend-reports-export`](https://github.com/Luffy610/SyncGate/pull/7) (PR #7) | 5 | 28-10-2026 | 31 server |
| 6 | Encrypted `.sgbackup`, passphrase, verified restore, nightly job | [`feature/backend-backup-restore`](https://github.com/Luffy610/SyncGate/pull/8) (PR #8) | 6 | 28-10-2026 | 43 server |
| 7 | Licence: trial, activation, dated states, signed token | [`feature/backend-licence`](https://github.com/Luffy610/SyncGate/pull/9) (PR #9) | 7 | 28-10-2026 | 48 server |
| 8 | CSV option in the app (its Tally removal is undone in step 10) | [`feature/export-csv-frontend`](https://github.com/Luffy610/SyncGate/pull/10) (PR #10) | 8 | 28-10-2026 | 236 app |
| 9 | Dart client `sg_api`, app wiring, server time, backend docs | [`feature/flutter-api-client`](https://github.com/Luffy610/SyncGate/pull/11) (PR #11) | 9 | 28-10-2026 | 25 client + live run |
| 10 | Tally restored and extended on the server (mapping + XML), CSV kept as third option, ADR-0023 | [`feature/tally-export`](https://github.com/Luffy610/SyncGate/pull/12) (PR #12) | 10 | 28-10-2026 | 56 server, 27 client, 236 app |
| 11 | Real Android services, restore screen, token revocation, setup-flow fixes, on-device full-stack test | [`feature/android-platform-services`](https://github.com/Luffy610/SyncGate/pull/13) (PR #13) | 11 | 09-11-2026 | 58 server, 27 client, 242 app, device test |
| 12 | This tracker and the pull-request guide | [`docs/backend-progress`](https://github.com/Luffy610/SyncGate/pull/14) (PR #14) | 12 | 12-11-2026 | docs only |

## 3. Bugs found by running the real stack (and fixed)

| Found by | Problem | Fix | Step |
|---|---|---|---|
| Device test | "Enrol first worker" read providers after an `await` and ended the owner's session, so the owner list came back empty | takes dependencies before the first await; `completeSetupAndEnterAdmin` keeps the session | 11 |
| Device test | The server refused to save setup progress once the owner existed, so a restart after the PIN step restarted the wizard | progress is accepted while the mode is still `setup`; going back to setup after finishing is still refused | 11 |
| Live run | Restore failed on DATE columns (legacy `java.sql.Date` shifted by time zone) | read columns as `java.time` types | 6 |
| Review | Export of unmapped Tally workers | left out and counted in `X-Unmapped` | 10 |
| Tooling | The import checker crashed on Android build output | skips `build`, `.dart_tool`, `.gradle` | 11 |

## 4. Open items, in the order they unblock the product

1. Face recognition and the camera (`packages/sg_vision`), then swap `FaceRecognitionPort` to the real matcher. Owner: written separately.
2. Run `V2__append_only_triggers.sql` on a real PostgreSQL and add a Postgres container test.
3. HTTPS and certificate pinning; per-phone device keys with attestation.
4. Google Drive client behind `BackupStore`.
5. Show a message when an API error has no screen of its own (server down mid-action).
6. Recorded Hindi voice clips (ADR-0016) instead of text-to-speech; screen dimming at the gate.
7. Tally XML import QA against a real Tally Prime company.
8. iOS: Mac access, Swift native code, Xcode flavour schemes.
9. Legal items that gate GA: TBD-L1 (legal basis text), TBD-L2 (model licences), TBD-L3 (retention periods).

## 5. How to keep this page current

* One row in section 2 per step; the PR link is in the Branch column (see [pull-requests.md](pull-requests.md)). PRs #3 to #14 were opened on 12-11-2026, all against `master`, with Luffy610 as reviewer, none merged yet.
* When a bug is found by a real run, add it to section 3 with the step that fixed it.
* Re-run `melos run analyze`, `melos run test`, `cd services/api && ./mvnw test` and the device test before changing a status to ✅.
