# SyncGate back end (Spring Boot)

This is the server half of SyncGate Phase 1: a Spring Boot 4 REST API in
[`services/api`](../../services/api) and a Dart client for it in
[`packages/sg_api`](../../packages/sg_api). The Flutter app talks to it through the
repository interfaces it already had, so no screen changed to use it.

> **Face matching is not here.** Detection, liveness, embedding and 1:N matching run on the
> phone (ADR-0006/0007/0009) and are written separately. The server only receives *who* matched
> and the scores. See [Where the face code goes](#where-the-face-code-goes).

## Contents

1. [How it fits together](#how-it-fits-together)
2. [Run it](#run-it)
3. [Frontend ↔ backend map](#frontend--backend-map)
4. [API reference](#api-reference)
5. [Security](#security)
6. [Data and no-data-loss guarantees](#data-and-no-data-loss-guarantees)
7. [Where the face code goes](#where-the-face-code-goes)
8. [Tests](#tests)
9. [Git workflow used](#git-workflow-used)
10. [Known limits](#known-limits)

## How it fits together

```
Flutter screens (apps/mobile/lib/src/features)        unchanged
        │ watch / call
        ▼
Riverpod providers (src/app/providers.dart)           bound at start-up
        │
        ├─ dev flavour, main_dev.dart ........ in-memory fakes (src/dev/fakes)      no server needed
        └─ main_dev_api.dart ................. sg_api  ──HTTP/JSON──►  Spring Boot  ──►  H2 file DB (dev)
                                                                                         PostgreSQL (prod)
        camera / voice / kiosk .............. still scripted fakes until the native code exists
```

Layers inside the server (`services/api/src/main/java/in/syncgate/api`):

| Package | Responsibility |
|---|---|
| `security` | JWT (Nimbus HS256), capability checks, first-run setup window, rate limit, headers |
| `user` | PIN login (Argon2id), lockout, owner creation, recovery code |
| `worker` | Workers, departments, contractors, consents, erasure |
| `shift` | Shift windows |
| `settings` | Single-row app settings |
| `attendance` | Append-only hash-chained events, manual marks, corrections, exceptions |
| `recognition` | **The seam for face matching** (`FaceRecognitionPort`, mock today) |
| `report` | Daily view, monthly muster, Excel and CSV export |
| `backup` | `.sgbackup` format, passphrase, restore with verification |
| `licence` | Trial, activation, dates-driven state, Ed25519 token |
| `audit` | Hash-chained audit log |
| `common` | Clock, UUIDv7, hash chain, error model, DB helpers |

## Run it

You need **Java 17**. Nothing else: the Maven wrapper downloads Maven.

```bash
cd services/api
./mvnw spring-boot:run          # dev profile: H2 file database in services/api/data
```

The API listens on `http://localhost:8080` (from the Android emulator that is `http://10.0.2.2:8080`).
Check it: `curl http://localhost:8080/actuator/health` → `{"status":"UP"}`.

The **dev profile** is for your machine only. It uses a demo clock that starts at the app's demo time
(Saturday 24-10-2026 05:52, then runs in real time) so the Flutter demo data and the server agree, and
demo secrets that the production profile refuses to start with.

Then run the app against it:

```bash
cd apps/mobile
flutter run --flavor dev -t lib/main_dev_api.dart --dart-define-from-file=env/dev.json
```

The first launch shows the setup wizard (the server has no owner yet). Create the owner PIN, enrol a worker,
then use the debug panel (long-press the logo at the gate) to make the scripted camera "walk up". The mark is
written to the server database. Stop the app, start it again: the data is still there.

To start from nothing, stop the API and delete `services/api/data/`.

### Production profile

```bash
SPRING_PROFILES_ACTIVE=prod \
SYNCGATE_DB_URL=jdbc:postgresql://db:5432/syncgate SYNCGATE_DB_USER=... SYNCGATE_DB_PASSWORD=... \
SYNCGATE_JWT_SECRET=<32+ random bytes> \
SYNCGATE_MASTER_KEY=<base64 of 32 random bytes> \
SYNCGATE_DEVICE_KEYS=<one or more 16+ char keys, comma separated> \
java -jar services/api/target/api-0.1.0-SNAPSHOT.jar
```

The app **refuses to start** if a secret is missing or short, still looks like a development value, if the
demo clock or the licence mock is on, or if Argon2 memory is below 16 MiB (`StartupGuard`).
The Postgres-only migration `V2__append_only_triggers.sql` makes the database itself reject `UPDATE`/`DELETE`
on events, audit and consents. *It has not been run against a real PostgreSQL in this repo's tests (no Docker
available); run the Flyway migration once on a staging Postgres before relying on it.*

## Frontend ↔ backend map

Every Flutter repository/service interface in `sg_domain` has one API-backed implementation in `sg_api`.
`ApiBackend` builds them all around one `ApiClient`; `apps/mobile/lib/src/dev/dev_overrides.dart`
(`devApiOverrides`) binds them to the providers.

| Flutter interface (`sg_domain`) | Implementation (`sg_api`) | Endpoints | Server code |
|---|---|---|---|
| `SettingsRepository` | `ApiSettingsRepository` | `GET/PUT /settings` | `settings/` |
| `UserRepository` | `ApiUserRepository` | `GET /setup/status`, `POST /auth/owner`, `/auth/login`, `/auth/reset-owner-pin`, `GET /users`, `PUT /users/{id}/pin` | `user/` |
| `WorkerRepository` | `ApiWorkerRepository` | `/workers…`, `/departments`, `/contractors` | `worker/` |
| `ConsentRepository` | `ApiConsentRepository` | `POST /consents`, `GET /consents/{id}` | `worker/` |
| `ShiftRepository` | `ApiShiftRepository` | `GET /shifts`, `PUT /shifts/{id}` | `shift/` |
| `AttendanceRepository` | `ApiAttendanceRepository` | `POST /attendance/face-marks`, `/manual-marks`, `/corrections`, `GET /attendance/day`, `/events`, `/last` | `attendance/` |
| `ExceptionRepository` | `ApiExceptionRepository` | `GET /exceptions`, `POST /exceptions`, `POST /exceptions/{id}/resolve` | `attendance/` |
| `AuditLog` | `ApiAuditLog` | `POST /audit`, `GET /audit` | `audit/` |
| `ReportService` | `ApiReportService` | `GET /reports/monthly`, `/reports/daily` | `report/` |
| `ExportService` | `ApiExportService` | `POST /exports` (returns the file) | `report/` |
| `BackupService` | `ApiBackupService` | `PUT /backups/passphrase`, `POST /backups`, `GET /backups/info`, `POST /backups/restore` | `backup/` |
| `LicenceService` | `ApiLicenceService` | `GET /licence`, `POST /licence/activate`, `/trial`, `/checkin` | `licence/` |
| `ClockService` | `ApiClock` (app) | `GET /time` | `common/TimeController` |
| `GateVisionService`, `EnrolmentCaptureService`, `CameraCheckService`, kiosk, voice, … | **still fakes** | none, they are on-device | – |

How the app behaves differently with a real server (and why):

* **The server stamps time and direction.** The app still computes them to decide what to show, but
  `AttendanceRepository.append` now returns the event *as stored*, and the gate shows that. A phone
  with a wrong clock cannot forge a mark.
* **Refusals are typed.** The server's `ALREADY_MARKED`, `MANUAL_LIMIT_REACHED`, `WRONG_PIN`, `LOCKED_OUT`,
  `DUPLICATE_WORKER_CODE`… are mapped to the existing sealed `Failure` classes (`failureOf` in `api_client.dart`),
  so the existing "already marked" and PIN screens work unchanged. Repositories signal them with `FailureException`.
* **Two tokens.** The gate phone holds a long-lived *device* token (can read, mark, mark manually, switch mode).
  Unlocking Admin with a PIN adds a short-lived *admin* token; returning to the gate drops it.
* **Setup without credentials.** Until an owner exists, the wizard calls the API with no token and gets a narrow
  "setup" role. Creating the owner closes that window for good.
* **Readable ids.** The app makes ids like `ev-123-0` and `shift-day`; `uuidFor()` maps them to a stable UUID,
  so a retried request is idempotent (the server answers with the existing record instead of duplicating).
* **Tally is gone.** Export is Excel and CSV (ADR-0023).
* **Lists refresh by polling** (3 to 20 s while a screen listens, and immediately after your own change).
  A push channel is Phase 2.

## API reference

Base path `/api/v1`. JSON in and out. Enum values use the Dart names (`checkIn`, `gateOperator`, `needsFace`).
Times are ISO-8601 UTC; dates are `yyyy-MM-dd`; months `yyyy-MM`.

**Errors** always look like `{"code": "...", "message": "...", "details": {...}}`:

| HTTP | `code` | Meaning |
|---|---|---|
| 400 | `VALIDATION` | Bad or missing field (`details` lists fields) |
| 401 | `UNAUTHENTICATED`, `WRONG_PIN` | No/invalid token; wrong PIN (`details.attemptsLeft`, `lockedForSeconds`) |
| 403 | `NOT_ALLOWED` | Your role may not do this |
| 404 | `NOT_FOUND` | No such record |
| 409 | `ALREADY_MARKED`, `MANUAL_LIMIT_REACHED`, `DUPLICATE_WORKER_CODE`, `SETUP_DONE`, `NOT_EMPTY`, `PASSPHRASE_NOT_SET` | Conflicts |
| 422 | `WORKER_UNDER_AGE`, `INVALID_CORRECTION`, `INVALID_LICENCE_KEY`, `BAD_PASSPHRASE`, `BACKUP_CORRUPT`, `BACKUP_TAMPERED`, `NOT_RECOGNISED` | Rule violations |
| 429 | `LOCKED_OUT`, `RATE_LIMITED` | Back off (`details.retryAfterSeconds`) |
| 503 | `NO_INTERNET` | Licence check could not reach the licence server (mock: key containing `NONET`) |

Who may call what (mirrors `RoleCapabilities` in `sg_domain`, enforced by `Capability.java`):

| Capability | device (gate phone) | gate operator | admin | owner | setup (no owner yet) |
|---|:-:|:-:|:-:|:-:|:-:|
| read workers, shifts, today, settings, licence, time | ✓ | ✓ | ✓ | ✓ | ✓ |
| face marks, manual marks, switch mode, write audit | ✓ | ✓ | ✓ | ✓ | – |
| enrol, edit, deactivate workers, consents | – | – | ✓ | ✓ | ✓ |
| shifts, settings, corrections, reports, exports, read audit | – | – | ✓ | ✓ | shifts/settings |
| erase worker, users and PINs, backups, licence changes | – | – | – | ✓ | licence |
| restore a backup (fresh install only) | – | – | – | ✓ | ✓ |

Endpoint list: see the table above for the grouping, or read the controllers; each is small and annotated
with the capability it needs (`@PreAuthorize("@caps.can('…')")`).

## Security

| Threat | Control |
|---|---|
| Guessing a PIN | Argon2id hashes; 5 free attempts then 30 s doubling to 15 min, stored in the database (survives restart); per-IP rate limit on `/auth/**`; unknown accounts cost the same time |
| Stolen/forged token | HS256 JWT with issuer, expiry (admin 30 min, device 30 days); secret ≥ 32 bytes, refused in prod if a dev value |
| A phone acting as admin | Capability table per role, checked on every route; the device token cannot read reports, users, backups or audit |
| Forged or back-dated attendance | Server stamps time; direction, cooldown and manual cap decided server-side under a chain lock; corrections limited to 62 days back and never in the future |
| Editing history | Append-only tables, SHA-256 hash chains (events, audit), Postgres triggers; `/attendance/verify` and `/audit/verify` re-check every row |
| Proxy attendance by a guard | Manual marks need a reason, are capped at 3 per worker per day and raise an exception |
| SQL injection | Every statement is parameterised; backup column names are matched against the live table before use |
| Formula injection in exports | Cells starting `= + - @` are neutralised in CSV; Excel cells are plain text/numbers, never formulas |
| Leaky errors | One error shape; no stack traces, class names or SQL; unexpected errors get a reference id in the log only |
| Browser attacks | CSP `default-src 'none'`, `X-Frame-Options: DENY`, `nosniff`, no-store, HSTS, CORS closed unless origins are configured; stateless, so no CSRF |
| Backup theft | AES-256-GCM, key from Argon2id of a passphrase the server never keeps; header authenticated; tampered or foreign files rejected |
| Restoring poisoned data | Only into a fresh install, in one transaction, re-verifying both chains, manifest counts and heads; any mismatch rolls back everything |
| Weak deployment | `StartupGuard` fails start-up on weak/dev secrets, demo clock or licence mock in prod |
| PIN or passphrase in logs | Request bodies are never logged by the app or the Dart client |

Not done (be honest): TLS termination and certificate pinning (deploy behind HTTPS; the Android dev flavour
allows cleartext only for `10.0.2.2`), a penetration test, Play Integrity/App Attest, and a PostgreSQL run of the
production migration.

## Data and no-data-loss guarantees

* Facts (events, audit, consents) are **inserted, never updated or deleted**; a correction is a new event that
  keeps the original visible. Erasing a worker removes personal data but keeps a wage-record stub when
  there is history.
* A mark is acknowledged only **after** the database commit. Chain appends hold a row lock, so two requests can never
  extend the same predecessor.
* A retry with the same event id returns the stored event instead of a duplicate.
* The dev database is a file (`services/api/data`), so data survives restarts. Production uses PostgreSQL.
* **Backups**: set the passphrase once (Settings → Backup), then `POST /backups`. The file is `.sgbackup`
  (`SGBK` header, Argon2id + AES-256-GCM + gzip). The last 10 are kept in `syncgate.backup.dir` (default
  `services/api/data/backups`; this local folder stands in for Google Drive, whose client is a second `BackupStore`
  implementation still to write). A nightly job runs at 22:30 when auto-backup is on.
* **Restore** (`POST /backups/restore`, multipart `file` + `passphrase`) works only on an empty install, so run it
  *before* setup. Every worker comes back as "needs a face" because face data is never in a backup.
* Export: `POST /exports` with `{"format":"excel"|"csv","month":"2026-10", …filters}` returns the file; each
  export is logged with its SHA-256.

## Where the face code goes

| Piece | Location | Status |
|---|---|---|
| Camera, detection, quality, alignment, liveness, embedding, matching | `packages/sg_vision/android/…` (Kotlin, CameraX + LiteRT) and `…/ios/…` (Swift) | **not written** |
| Dart contract the UI uses (`GateVisionService`, `EnrolmentCaptureService`, `CameraCheckService`, events `Match`, `NoMatch`, `QualityHint`…) | `packages/sg_vision/lib/src/` | exists |
| Scripted stand-in used today | `apps/mobile/lib/src/dev/fakes/fake_vision.dart` | exists |
| Template vault (encrypted face vectors, on the phone only) | `packages/sg_vision/android/.../vault/` | not written |
| Models and threshold tables with model cards | `ml/models/` (see ADR-0006, ADR-0009) | not written |
| Offline evaluation (FAR/FRR, liveness, fairness) | `ml/eval/` (ADR-0020) | not written |
| **Server-side seam** | `services/api/.../recognition/FaceRecognitionPort.java` | exists, mock |

How a match reaches the server today: the matcher emits `Match(workerId, score, margin, liveness)`; the gate
calls `MarkAttendance`, which now passes those three numbers into `AttendanceEvent`; `ApiAttendanceRepository`
sends them to `POST /attendance/face-marks`; `AttendanceService.markFace` asks `FaceRecognitionPort.verify()`
whether to accept them, then stamps the time and records the event.

To plug in the real thing:

1. Write the native pipeline in `packages/sg_vision` so that it implements `GateVisionService` and
   `EnrolmentCaptureService`, then bind it in the app's providers instead of the fakes. No server change needed.
2. Put the calibrated thresholds from the model card (`T_match`, margin, liveness) in a class implementing
   `FaceRecognitionPort`, annotate it `@ConditionalOnProperty(name="syncgate.recognition.mode", havingValue="real")`,
   and set that property. `MockFaceRecognition` then switches off automatically.
3. Face vectors must never be sent to the server or put in backups (ADR-0003, ADR-0010). The API has no field for
   them, and the protocol only carries scores.

## Tests

| Suite | Command | What it covers |
|---|---|---|
| Server (Spring, MockMvc, in-memory H2) | `cd services/api && ./mvnw test` | auth and lockout, roles, setup window, workers, attendance rules, tamper detection, reports, exports, backup/restore, licence, error hygiene |
| Dart client | `cd packages/sg_api && dart test` | auth flow, typed failures, payloads, id mapping, polling, offline handling (mock HTTP) |
| Client ↔ real server | start the API, then `cd packages/sg_api && SG_API_URL=http://localhost:8080 dart test test/live_api_test.dart` | the whole flow with the real Dart client against the real Spring app |
| Flutter app | `melos run test` or `cd apps/mobile && flutter test` | screens, roles, flows (fakes) |
| Static | `melos run analyze`, `melos run format:check` | lints, import boundaries |

## Git workflow used

One branch per feature, each stacked on the previous one, one or two feature-scoped commits per branch, tests green at
every commit. Merge them in this order (each PR is small to review):

| # | Branch | Contents |
|---|---|---|
| 1 | `feature/backend-api-scaffold` | Spring Boot project, config, schema, shared plumbing |
| 2 | `feature/backend-auth-security` | login, device token, audit chain, security config |
| 3 | `feature/backend-workers-shifts-settings` | workers, consents, shifts, settings |
| 4 | `feature/backend-attendance-exceptions` | events, manual marks, corrections, exceptions, recognition seam |
| 5 | `feature/backend-reports-export` | muster, daily view, Excel and CSV |
| 6 | `feature/backend-backup-restore` | `.sgbackup`, passphrase, restore |
| 7 | `feature/backend-licence` | licence state and token |
| 8 | `feature/export-csv-frontend` | remove Tally from the app, add CSV (ADR-0023) |
| 9 | `feature/flutter-api-client` | `sg_api`, wiring, `main_dev_api.dart`, docs |

Nothing has been pushed. Commit messages follow `feat(scope): …`.

## Known limits

* Face recognition, liveness and the native camera are not part of this work (by design, see above).
* Google Drive backup is not implemented; backups go to a local folder behind the `BackupStore` interface.
* The licence server is the same Spring app in mock mode; the standalone Go service in ADR-0014 is not built.
* Night-shift attribution in reports uses the calendar day of the IN (the full shift engine is a later step).
* Restore has an API but no Flutter screen yet.
* iOS: the Dart side works on both platforms; the iOS native code and Xcode flavour schemes still need a Mac.
* Staging and prod entry points are still unwired (they will bind `ApiBackend` the same way once the native
  vision code exists).
