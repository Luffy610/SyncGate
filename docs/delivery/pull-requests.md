# Pull requests for the back end and integration work

Every branch targets **`master`** (the repository's default branch; there is no `main`). The branches are
**stacked**: each one contains the one before it, so **merge them in the order below using "Create a merge commit"
(not squash, not rebase)**. After each merge, GitHub shrinks the next PR's diff to only its own changes.

Progress and open items: [backend-progress.md](backend-progress.md).

| # | PR | Branch | Pull request |
|---|---|---|---|
| 1 | feat(api): Spring Boot scaffold, schema and shared plumbing | `feature/backend-api-scaffold` | [PR #3](https://github.com/Luffy610/SyncGate/pull/3) |
| 2 | feat(api): PIN login, device token, audit chain and security config | `feature/backend-auth-security` | [PR #4](https://github.com/Luffy610/SyncGate/pull/4) |
| 3 | feat(api): workers, consents, shifts and settings | `feature/backend-workers-shifts-settings` | [PR #5](https://github.com/Luffy610/SyncGate/pull/5) |
| 4 | feat(api): attendance events, manual marks, corrections and exceptions | `feature/backend-attendance-exceptions` | [PR #6](https://github.com/Luffy610/SyncGate/pull/6) |
| 5 | feat(api): muster, daily view, Excel and CSV export | `feature/backend-reports-export` | [PR #7](https://github.com/Luffy610/SyncGate/pull/7) |
| 6 | feat(api): encrypted .sgbackup backup and verified restore | `feature/backend-backup-restore` | [PR #8](https://github.com/Luffy610/SyncGate/pull/8) |
| 7 | feat(api): licence state, trial, activation and signed token | `feature/backend-licence` | [PR #9](https://github.com/Luffy610/SyncGate/pull/9) |
| 8 | feat(app): CSV export option (Tally removal is reverted in #10) | `feature/export-csv-frontend` | [PR #10](https://github.com/Luffy610/SyncGate/pull/10) |
| 9 | feat(app): Dart API client (sg_api) and wiring to the back end | `feature/flutter-api-client` | [PR #11](https://github.com/Luffy610/SyncGate/pull/11) |
| 10 | feat: bring Tally back with a server side; keep CSV as a third export | `feature/tally-export` | [PR #12](https://github.com/Luffy610/SyncGate/pull/12) |
| 11 | feat: real Android services, restore screen, token revocation and device test | `feature/android-platform-services` | [PR #13](https://github.com/Luffy610/SyncGate/pull/13) |
| 12 | docs: back-end progress tracker and pull-request guide | `docs/backend-progress` | [PR #14](https://github.com/Luffy610/SyncGate/pull/14) |

Opened on 12-11-2026 as PRs #3 to #14, each with Luffy610 as reviewer. None merged yet.

## Descriptions

### 1. feat(api): Spring Boot scaffold, schema and shared plumbing

`feature/backend-api-scaffold` into `master`

Starts services/api: Maven wrapper, typed config, a startup guard that refuses weak secrets, server clock, UUIDv7, hash-chain service, error model, Flyway schema v1 and the Postgres append-only triggers.

**Tests:** Builds; no endpoints yet.

### 2. feat(api): PIN login, device token, audit chain and security config

`feature/backend-auth-security` into `master`

Argon2id PINs with database-backed lockout, first-run setup window that closes once the owner exists, JWT access tokens, role/capability table mirroring the Flutter RoleCapabilities, rate limiting, hardened headers, hash-chained audit log.

**Tests:** 9 server tests.

### 3. feat(api): workers, consents, shifts and settings

`feature/backend-workers-shifts-settings` into `master`

Enrolment with the under-18 block and unique codes, append-only consents, wage-stub erasure, idempotent shift upsert, settings where the gate device may only change the mode.

**Tests:** 14 server tests.

### 4. feat(api): attendance events, manual marks, corrections and exceptions

`feature/backend-attendance-exceptions` into `master`

Server-stamped, hash-chained attendance with cooldown, direction, manual-entry cap and idempotent retries; missing-OUT detection; FaceRecognitionPort (mock) where the real matcher plugs in.

**Tests:** 23 server tests including tamper detection.

### 5. feat(api): muster, daily view, Excel and CSV export

`feature/backend-reports-export` into `master`

Reports computed on demand from the events (late, half day, weekly off, overtime, open exceptions). Excel and CSV exports with a logged SHA-256; CSV is UTF-8 with BOM and defuses spreadsheet formulas.

**Tests:** 31 server tests.

### 6. feat(api): encrypted .sgbackup backup and verified restore

`feature/backend-backup-restore` into `master`

Argon2id + AES-256-GCM + gzip format, passphrase, local-folder store standing in for Google Drive, nightly job. Restore only into a pristine install, in one transaction, re-verifying both hash chains and the manifest.

**Tests:** 43 server tests.

### 7. feat(api): licence state, trial, activation and signed token

`feature/backend-licence` into `master`

Dates drive the state (trial, active, grace, restricted); export and backup are never blocked. Ed25519-signed token. Mock activation mirrors the Flutter fake.

**Tests:** 48 server tests.

### 8. feat(app): CSV export option (Tally removal is reverted in #10)

`feature/export-csv-frontend` into `master`

Adds CSV to the export section and strings (en/hi). It also removed Tally, which was a mistake and is undone by the Tally PR; review the two together.

**Tests:** 236 app tests.

### 9. feat(app): Dart API client (sg_api) and wiring to the back end

`feature/flutter-api-client` into `master`

New pure-Dart package implementing every sg_domain repository over HTTP (two-token auth, typed failures, idempotent ids, polling streams). Attendance append returns the stored event. main_dev_api.dart runs the app on the real API. Back-end guide added.

**Tests:** 27 client tests plus a live end-to-end test.

### 10. feat: bring Tally back with a server side; keep CSV as a third export

`feature/tally-export` into `master`

Reverts the Tally removal. Server: tally_mappings table (backed up, dropped on erasure), mapping endpoints and the Tally Prime import file built with an XML writer (names escaped, unmapped workers counted). Client: mapping repository. ADR-0023 amends ADR-0015.

**Tests:** 56 server, 27 client, 236 app tests. The XML still needs import QA in real Tally Prime.

### 11. feat: real Android services, restore screen, token revocation and device test

`feature/android-platform-services` into `master`

Share sheet, text-to-speech, biometrics, keep-awake, screen pinning, hardware check, file chooser. Restore-from-backup screen. Tokens revoked when Admin returns to the gate. Fixes two bugs found by running the real stack. On-device full-stack test and script.

**Tests:** 58 server, 27 client, 242 app tests; device test passes on an Android emulator.

### 12. docs: back-end progress tracker and pull-request guide

`docs/backend-progress` into `master`

Adds docs/delivery/backend-progress.md (state per layer, step log, bugs found, open items) and this pull-request guide.

**Tests:** Docs only.

## Checklist for each PR

- [ ] `melos run analyze` and `melos run test` pass
- [ ] `cd services/api && ./mvnw test` passes
- [ ] The row in [backend-progress.md](backend-progress.md) is updated
- [ ] Merged with a merge commit, in the order above
