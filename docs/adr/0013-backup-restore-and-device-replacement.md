# ADR-0013: Passphrase-encrypted backups (no biometrics) to a local file or the owner's Google Drive

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Security, Product
- **Related:** FR-OFF-02..05, FR-LIC-06 · NFR-SEC-04 · TC-01 · §9.3 · Risk R-4 · Design 17 · ADR-0010, ADR-0014

## Context

With one phone per factory, **the phone is the only copy** of attendance history, which is wage evidence. Phones break, get stolen and get reset. Backups are therefore P0 (FR-OFF-02). They must also:

- **never contain templates** (FR-OFF-03),
- be encrypted with a key **the vendor never holds** (NFR-SEC-04),
- be restorable by a non-technical owner on a new phone.

## Decision

### 1. Backup contents

| Included | Excluded |
|---|---|
| Workers, consents, shifts, rules, attendance events, corrections, exceptions, audit log, users (PIN hashes), settings, export history, licence ID | **Templates, template metadata vectors, any image**, `DB_KEY`, `VAULT_KEY`, device keys |

### 2. Format: `.sgbackup`

```
header (plaintext, 64 B): magic "SGBK", format_version, created_at, factory_id,
                          kdf params (Argon2id m=64 MiB, t=3, p=1), salt(16), nonce(12)
body:   AES-256-GCM( zstd( SQLite logical dump (JSON Lines per table) + manifest.json ) )
        AAD = header bytes
manifest.json: table row counts, audit chain head hash, app version, schema version
```

- **Key:** `KEK = Argon2id(backup_passphrase, salt)`. A random `DEK` encrypts the body, and the DEK is wrapped with the KEK inside the body header. Changing the passphrase re-wraps the DEK on the next backup.
- **Backup passphrase:** set by the owner at first backup. It is at least 8 characters. We suggest 4 random words in the owner's language. It is **separate from the admin PIN**. The app shows it once and offers to print or write it down. **We cannot recover it.** This is said plainly in the UI.
- The phone keeps the passphrase-derived key wrapped in Keystore/Keychain, so automatic backups need no typing.

### 3. Destinations

| Destination | How | Default |
|---|---|---|
| **Local file → share sheet** | `share_plus`: WhatsApp to self, email, USB/Files, Drive app | Always available |
| **Owner's Google Drive (automatic)** | `google_sign_in` + Drive REST v3 with scope **`drive.file`** (the app sees only the files it creates; a non-sensitive scope); folder "SyncGate Backups"; keeps the last **10** backups | Optional; on by default after sign-in |
| iCloud Drive | Via the share sheet / Files only (no CloudKit integration in Phase 1) | Manual |

- Automatic backup runs **daily at a quiet hour** (default 22:30, configurable), when online and charging. On Android this uses `WorkManager`; on iOS, `BGProcessingTask` with an in-app fallback when Admin opens.
- **Reminder (FR-OFF-04):** if no successful backup for **7 days** (configurable), Today and Backup show an amber card (designs 10, 17). At 14 days, gate mode also shows a small owner-only badge after unlock.

### 4. Restore and device replacement (FR-OFF-05, FR-LIC-06)

1. On the new phone: install → "Restore from backup" in the setup wizard → pick the file (or sign in to Drive) → enter the passphrase.
2. Integrity check: GCM tag, manifest row counts, audit-chain verification.
3. **Licence transfer:** the app calls `/transfer` with the licence ID and the new device key. The server deactivates the old device ([ADR-0014](0014-licensing-and-licence-server.md)). If offline, a 7-day provisional mode lets the gate run until the transfer is confirmed.
4. All workers appear with **"Needs face"** (design 11). Gate mode marks them **only through the guard fallback** until they re-enrol. A "Re-enrol everyone" queue walks the owner through it (~30 s per worker; ≤15 min for 25).

### 5. Lost or stolen phone (§9.3, CMP-07)

- The owner reports the loss from the new phone ("Report phone lost", design 17) or via support. This creates an **incident record** with a timestamp, revokes the old device's licence and queues a **wipe command**.
- If the old phone ever checks in, it receives the signed wipe command. It then destroys its keys (crypto-shredding), which renders DB and vault unreadable, and resets the app.
- Even without the wipe, data on the old phone is unreadable without its hardware-bound keys and the device unlock ([ADR-0010](0010-local-storage-and-encryption.md)).
- The app generates a **pre-filled breach-notification template** for the 72-hour window (CMP-07).

## Options considered

| Option | Verdict |
|---|---|
| Vendor cloud backup | Rejected: the vendor would hold personal data, contradicting §9.1 positioning. |
| Key escrowed by vendor for recovery | Rejected: violates NFR-SEC-04. |
| `drive.appdata` (hidden folder) | Rejected: owners want to *see* their backups; `drive.file` gives that with equal least-privilege. |
| Back up templates encrypted | Rejected: TC-01 / FR-OFF-03, and templates would then exist off-device. |
| OS-level backups (iCloud/Google) | Explicitly disabled ([ADR-0010](0010-local-storage-and-encryption.md)). |

## Consequences

- If the owner loses both the phone **and** the backup passphrase, history is gone. The UI must make this unmissable, and support scripts must say it plainly.
- Re-enrolment after replacement is a real cost. It stays acceptable only because the headcount is small.
