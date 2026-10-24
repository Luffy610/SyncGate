# ADR-0010: Encrypted SQLite (SQLCipher via Drift) and a separate native template vault

- **Status:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Security
- **Related:** NFR-SEC-01, NFR-SEC-02, NFR-SEC-04 · NFR-REL-02 · FR-OFF-03 · CMP-06 · TC-01 · ADR-0003, ADR-0011, ADR-0013

## Context

All data lives on one phone, which may be lost, stolen, borrowed or rooted. We hold two very different kinds of data:

1. **Biometric templates.** The most sensitive. They must never leave the device, not even in a backup.
2. **Everything else**: workers, consents, shifts, attendance events, audit log, settings, licence. This is sensitive personal data, and it must be backed up.

## Decision

### 1. Two stores, two keys

| Store | Technology | Contents | Key | In OS/cloud backups | In SyncGate backups |
|---|---|---|---|---|---|
| **App DB** | SQLite via **Drift**, encrypted with **SQLCipher 4** (AES-256-CBC + HMAC-SHA512 per page, PBKDF2 off since we use a raw key) | All non-biometric data | `DB_KEY` (256-bit random) | **Excluded** | **Yes** (re-encrypted, [ADR-0013](0013-backup-restore-and-device-replacement.md)) |
| **TemplateVault** | Native file per worker (Kotlin/Swift), **AES-256-GCM**, nonce per write, AAD = `worker_id‖slot‖model_version` | Embedding vectors only | `VAULT_KEY` (256-bit random) | **Excluded** | **Never** |

Dart never sees `VAULT_KEY` or a vector ([ADR-0003](0003-app-architecture-and-repository-layout.md)). It sees `DB_KEY` only through `KeyManager`, which hands it straight to SQLCipher.

### 2. Key management

| | Android | iOS |
|---|---|---|
| Wrapping key | AES-256-GCM key in **Android Keystore**, `setIsStrongBoxBacked(true)` when available, else TEE. `setUserAuthenticationRequired(false)`, because the gate runs unattended. Non-exportable. | **Secure Enclave** P-256 key (`kSecAttrTokenIDSecureEnclave`) used for ECIES wrapping. On devices without SE, a Keychain AES key. |
| Wrapped secrets | `DB_KEY`, `VAULT_KEY` stored wrapped in app-private files | Wrapped secrets stored as Keychain items, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| "This device only" | Keystore keys are bound to the device | `…ThisDeviceOnly` stops migration to a new iPhone or iCloud Keychain |
| Attestation | Key attestation checked at activation (reported to the licence server as pass/fail only) | App Attest ([ADR-0014](0014-licensing-and-licence-server.md)) |

`AfterFirstUnlock` (not `WhenUnlocked`) is required so the gate keeps working with the screen locked or dimmed. The device must still have been unlocked once since boot.

### 3. Excluding data from OS backups

- Android: `android:allowBackup="false"`, plus `dataExtractionRules` (Android 12+) excluding all domains from cloud backup **and** device-to-device transfer. `android:fullBackupContent` excludes everything on older versions.
- iOS: the DB and vault directories have `NSURLIsExcludedFromBackupKey = true`. Keychain items are `ThisDeviceOnly`. Files use `NSFileProtectionCompleteUntilFirstUserAuthentication`.

So a new phone restored from iCloud or Google backup gets **no** SyncGate data. Restore is only possible through a SyncGate backup file, by design.

### 4. Durability (NFR-REL-02)

- SQLite in **WAL** mode, `synchronous=FULL` for the `attendance_events` and `audit_log` writes. The gate shows the green confirmation only **after** the transaction commits.
- Vault writes go to a temp file + `fsync` + atomic rename.
- Corruption check (`PRAGMA integrity_check`) runs daily at a quiet hour and on start after a crash.

### 5. Secure deletion

Deleting a worker's templates overwrites the vault file with random bytes, deletes it, and drops the per-file nonce. SQLCipher runs with `secure_delete = ON`. Flash wear-levelling means true erasure cannot be guaranteed. Since everything is encrypted under device-bound keys, **crypto-shredding** (destroying the key) is the real guarantee for a full wipe (e.g. the remote-wipe command, [ADR-0017](0017-security-hardening-and-privacy-dpdp.md)).

## Options considered

| Option | Verdict |
|---|---|
| Templates in the SQLCipher DB | Rejected: the DB is backed up and opened from Dart. Separation is the cleanest way to guarantee TC-01. |
| Isar / Hive / ObjectBox | Rejected: weaker or no at-rest encryption story, less mature migrations; relational queries suit reports. |
| Realm | Rejected: Atlas Device Sync deprecation makes its future unclear. |
| Encrypt individual columns only | Rejected: metadata leaks, more room for mistakes. |
| Require user auth for keys | Rejected: the gate runs unattended. |

## Consequences

- Losing the phone's keys (factory reset) makes local data unrecoverable without a SyncGate backup. This is intentional and is explained during setup and in the backup screen (design 17).
- The `sqlcipher_flutter_libs` dependency adds ~6–7 MB per ABI. That fits the 80 MB budget.
