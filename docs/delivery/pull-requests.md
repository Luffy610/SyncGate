# Pull requests for the back end and integration work

Every branch targets **`master`** (the repository's default branch; there is no `main`). The branches are
**stacked**: each one contains the one before it, so **merge them in the order below using "Create a merge commit"
(not squash, not rebase)**. After each merge, GitHub shrinks the next PR's diff to only its own changes.

Progress and open items: [backend-progress.md](backend-progress.md).

| # | PR | Branch | Open it |
|---|---|---|---|
| 1 | feat(api): Spring Boot scaffold, schema and shared plumbing | `feature/backend-api-scaffold` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-api-scaffold?quick_pull=1&title=feat(api)%3A%20Spring%20Boot%20scaffold%2C%20schema%20and%20shared%20plumbing&body=Starts%20services%2Fapi%3A%20Maven%20wrapper%2C%20typed%20config%2C%20a%20startup%20guard%20that%20refuses%20weak%20secrets%2C%20server%20clock%2C%20UUIDv7%2C%20hash-chain%20service%2C%20error%20model%2C%20Flyway%20schema%20v1%20and%20the%20Postgres%20append-only%20triggers.%0A%0ATests%3A%20Builds%3B%20no%20endpoints%20yet.%0A%0AMerge%20order%3A%201%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 2 | feat(api): PIN login, device token, audit chain and security config | `feature/backend-auth-security` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-auth-security?quick_pull=1&title=feat(api)%3A%20PIN%20login%2C%20device%20token%2C%20audit%20chain%20and%20security%20config&body=Argon2id%20PINs%20with%20database-backed%20lockout%2C%20first-run%20setup%20window%20that%20closes%20once%20the%20owner%20exists%2C%20JWT%20access%20tokens%2C%20role%2Fcapability%20table%20mirroring%20the%20Flutter%20RoleCapabilities%2C%20rate%20limiting%2C%20hardened%20headers%2C%20hash-chained%20audit%20log.%0A%0ATests%3A%209%20server%20tests.%0A%0AMerge%20order%3A%202%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 3 | feat(api): workers, consents, shifts and settings | `feature/backend-workers-shifts-settings` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-workers-shifts-settings?quick_pull=1&title=feat(api)%3A%20workers%2C%20consents%2C%20shifts%20and%20settings&body=Enrolment%20with%20the%20under-18%20block%20and%20unique%20codes%2C%20append-only%20consents%2C%20wage-stub%20erasure%2C%20idempotent%20shift%20upsert%2C%20settings%20where%20the%20gate%20device%20may%20only%20change%20the%20mode.%0A%0ATests%3A%2014%20server%20tests.%0A%0AMerge%20order%3A%203%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 4 | feat(api): attendance events, manual marks, corrections and exceptions | `feature/backend-attendance-exceptions` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-attendance-exceptions?quick_pull=1&title=feat(api)%3A%20attendance%20events%2C%20manual%20marks%2C%20corrections%20and%20exceptions&body=Server-stamped%2C%20hash-chained%20attendance%20with%20cooldown%2C%20direction%2C%20manual-entry%20cap%20and%20idempotent%20retries%3B%20missing-OUT%20detection%3B%20FaceRecognitionPort%20(mock)%20where%20the%20real%20matcher%20plugs%20in.%0A%0ATests%3A%2023%20server%20tests%20including%20tamper%20detection.%0A%0AMerge%20order%3A%204%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 5 | feat(api): muster, daily view, Excel and CSV export | `feature/backend-reports-export` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-reports-export?quick_pull=1&title=feat(api)%3A%20muster%2C%20daily%20view%2C%20Excel%20and%20CSV%20export&body=Reports%20computed%20on%20demand%20from%20the%20events%20(late%2C%20half%20day%2C%20weekly%20off%2C%20overtime%2C%20open%20exceptions).%20Excel%20and%20CSV%20exports%20with%20a%20logged%20SHA-256%3B%20CSV%20is%20UTF-8%20with%20BOM%20and%20defuses%20spreadsheet%20formulas.%0A%0ATests%3A%2031%20server%20tests.%0A%0AMerge%20order%3A%205%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 6 | feat(api): encrypted .sgbackup backup and verified restore | `feature/backend-backup-restore` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-backup-restore?quick_pull=1&title=feat(api)%3A%20encrypted%20.sgbackup%20backup%20and%20verified%20restore&body=Argon2id%20%2B%20AES-256-GCM%20%2B%20gzip%20format%2C%20passphrase%2C%20local-folder%20store%20standing%20in%20for%20Google%20Drive%2C%20nightly%20job.%20Restore%20only%20into%20a%20pristine%20install%2C%20in%20one%20transaction%2C%20re-verifying%20both%20hash%20chains%20and%20the%20manifest.%0A%0ATests%3A%2043%20server%20tests.%0A%0AMerge%20order%3A%206%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 7 | feat(api): licence state, trial, activation and signed token | `feature/backend-licence` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/backend-licence?quick_pull=1&title=feat(api)%3A%20licence%20state%2C%20trial%2C%20activation%20and%20signed%20token&body=Dates%20drive%20the%20state%20(trial%2C%20active%2C%20grace%2C%20restricted)%3B%20export%20and%20backup%20are%20never%20blocked.%20Ed25519-signed%20token.%20Mock%20activation%20mirrors%20the%20Flutter%20fake.%0A%0ATests%3A%2048%20server%20tests.%0A%0AMerge%20order%3A%207%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 8 | feat(app): CSV export option (Tally removal is reverted in #10) | `feature/export-csv-frontend` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/export-csv-frontend?quick_pull=1&title=feat(app)%3A%20CSV%20export%20option%20(Tally%20removal%20is%20reverted%20in%20%2310)&body=Adds%20CSV%20to%20the%20export%20section%20and%20strings%20(en%2Fhi).%20It%20also%20removed%20Tally%2C%20which%20was%20a%20mistake%20and%20is%20undone%20by%20the%20Tally%20PR%3B%20review%20the%20two%20together.%0A%0ATests%3A%20236%20app%20tests.%0A%0AMerge%20order%3A%208%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 9 | feat(app): Dart API client (sg_api) and wiring to the back end | `feature/flutter-api-client` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/flutter-api-client?quick_pull=1&title=feat(app)%3A%20Dart%20API%20client%20(sg_api)%20and%20wiring%20to%20the%20back%20end&body=New%20pure-Dart%20package%20implementing%20every%20sg_domain%20repository%20over%20HTTP%20(two-token%20auth%2C%20typed%20failures%2C%20idempotent%20ids%2C%20polling%20streams).%20Attendance%20append%20returns%20the%20stored%20event.%20main_dev_api.dart%20runs%20the%20app%20on%20the%20real%20API.%20Back-end%20guide%20added.%0A%0ATests%3A%2027%20client%20tests%20plus%20a%20live%20end-to-end%20test.%0A%0AMerge%20order%3A%209%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 10 | feat: bring Tally back with a server side; keep CSV as a third export | `feature/tally-export` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/tally-export?quick_pull=1&title=feat%3A%20bring%20Tally%20back%20with%20a%20server%20side%3B%20keep%20CSV%20as%20a%20third%20export&body=Reverts%20the%20Tally%20removal.%20Server%3A%20tally_mappings%20table%20(backed%20up%2C%20dropped%20on%20erasure)%2C%20mapping%20endpoints%20and%20the%20Tally%20Prime%20import%20file%20built%20with%20an%20XML%20writer%20(names%20escaped%2C%20unmapped%20workers%20counted).%20Client%3A%20mapping%20repository.%20ADR-0023%20amends%20ADR-0015.%0A%0ATests%3A%2056%20server%2C%2027%20client%2C%20236%20app%20tests.%20The%20XML%20still%20needs%20import%20QA%20in%20real%20Tally%20Prime.%0A%0AMerge%20order%3A%2010%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 11 | feat: real Android services, restore screen, token revocation and device test | `feature/android-platform-services` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...feature/android-platform-services?quick_pull=1&title=feat%3A%20real%20Android%20services%2C%20restore%20screen%2C%20token%20revocation%20and%20device%20test&body=Share%20sheet%2C%20text-to-speech%2C%20biometrics%2C%20keep-awake%2C%20screen%20pinning%2C%20hardware%20check%2C%20file%20chooser.%20Restore-from-backup%20screen.%20Tokens%20revoked%20when%20Admin%20returns%20to%20the%20gate.%20Fixes%20two%20bugs%20found%20by%20running%20the%20real%20stack.%20On-device%20full-stack%20test%20and%20script.%0A%0ATests%3A%2058%20server%2C%2027%20client%2C%20242%20app%20tests%3B%20device%20test%20passes%20on%20an%20Android%20emulator.%0A%0AMerge%20order%3A%2011%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |
| 12 | docs: back-end progress tracker and pull-request guide | `docs/backend-progress` | [new pull request](https://github.com/Luffy610/SyncGate/compare/master...docs/backend-progress?quick_pull=1&title=docs%3A%20back-end%20progress%20tracker%20and%20pull-request%20guide&body=Adds%20docs%2Fdelivery%2Fbackend-progress.md%20(state%20per%20layer%2C%20step%20log%2C%20bugs%20found%2C%20open%20items)%20and%20this%20pull-request%20guide.%0A%0ATests%3A%20Docs%20only.%0A%0AMerge%20order%3A%2012%20of%2012%20(stacked%2C%20see%20docs%2Fdelivery%2Fpull-requests.md).) |

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
