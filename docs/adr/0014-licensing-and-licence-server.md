# ADR-0014: Ed25519-signed offline licence tokens; a minimal metadata-only licence server in India

- **Status:** Accepted (licensing model, token design) · Proposed (server stack — confirm before M2)
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product, Finance, Legal
- **Related:** FR-LIC-01..07 · FR-PLT-05 · TC-04 · NFR-SEC-03 · Risk R-10 · D-3 · ADR-0013, ADR-0017

## Context

Pricing is an **annual licence per device** with no worker-count fees (FR-LIC-02). The licence must:

- work **offline** (TC-04),
- bind to **one device** (FR-PLT-05),
- resist APK tampering (R-10),
- **never block data export or wages** (FR-LIC-04),
- send the vendor **only metadata** (FR-LIC-05).

## Decision

### 1. Licence token

- Format: **PASETO v4.public**, which uses Ed25519. It is a compact, versioned format, safer by default than hand-rolled JWT.
- Claims:

```json
{
  "lic": "LIC-01J9…",            // licence ID (UUIDv7)
  "fac": "FAC-01J9…",            // factory ID (opaque)
  "dev": "base64url(sha256(device_pubkey))",
  "plan": "phase1-standard",      // TBD with D-3
  "max_workers": 25,              // advisory unless D-3 makes it a hard limit
  "iat": "2026-10-24T05:00:00Z",
  "nbf": "2026-10-24T05:00:00Z",
  "exp": "2027-10-24T23:59:59+05:30",
  "chk": "2026-11-07T00:00:00Z",  // next check-in due
  "grace_days": 30                // TBD (FR-LIC-03)
}
```

- The app embeds the **public keys** (current + next, for rotation) and verifies offline in `sg_domain.LicenceVerifier`.
- **Device binding:** at first run the app creates a **device key pair** (Ed25519 in software, wrapped by a Keystore/Secure Enclave key; or P-256 native in SE/StrongBox). Activation sends the public key plus an attestation:
  - Android: **Play Integrity API** verdict. Sideloaded APKs get `UNRECOGNIZED_VERSION`; these are accepted for the sideload channel, but flagged.
  - iOS: **App Attest** (`DCAppAttestService`) assertion.
- Check-ins are signed by the device key, so a copied token is useless on another phone.

### 2. States and what they allow

| State | Trigger | Gate capture | Enrol | Reports & export | Banner |
|---|---|---|---|---|---|
| Trial (30 days) | Setup without key | ✓ | ✓ | ✓ | "Trial: N days left" |
| Active | Valid token, check-in on time | ✓ | ✓ | ✓ | — |
| Check-in overdue | `now > chk` | ✓ | ✓ | ✓ | "Connect to the internet once" |
| Grace | `now > exp` or check-in overdue by > `grace_days` | ✓ | ✓ | ✓ | Daily owner warning |
| Restricted | Grace ended | ✓ for 7 more days, then ✗ | ✗ | **✓ always** | Persistent |
| Revoked / wiped | Lost-phone report, transfer | ✗ | ✗ | Owner can still export once before the wipe, if the device is in hand | — |

**Rule:** export, backup and worker-rights functions are **never** disabled by licence state (FR-LIC-04).

Values of `grace_days` and the check-in interval are **TBD** (FR-LIC-03). Placeholders: check-in every 14 days, 30-day grace.

### 3. Licence server

| Aspect | Decision |
|---|---|
| Language / runtime | **Go** (single static binary, small attack surface) — *Proposed* |
| Data store | **PostgreSQL** |
| Hosting | AWS **ap-south-1 (Mumbai)**; container on ECS Fargate (or a single VM in early beta); RDS Postgres with encryption at rest; daily snapshots |
| API (OpenAPI in `services/licence/api.yaml`) | `POST /v1/activate` · `POST /v1/checkin` · `POST /v1/transfer` · `POST /v1/report-lost` · `GET /v1/keys` · internal `POST /v1/admin/*` (support console, SSO-protected) |
| Transport | TLS 1.3 (1.2 minimum); app pins the **SPKI** of the issuing CA intermediate + a backup pin (NFR-SEC-03) |
| Rate limiting | Per licence and per IP |
| Keys | Signing keys in **AWS KMS** (Ed25519 support), or an HSM-backed signer; yearly rotation with overlap |

### 4. What the server stores (FR-LIC-05)

| Stored | Not stored, ever |
|---|---|
| Licence ID, factory ID (opaque), plan, validity | Worker names, IDs, counts per person |
| Device public-key hash, platform, OS version, app version | Attendance data, templates, images |
| Last check-in time, attestation verdict (pass/fail) | Location |
| **Aggregate** counts: active workers (bucketed 0–10/11–25/26+), events last 14 days (bucketed) | Phone numbers of workers |
| Incident records (lost/transfer) with timestamps | |

The **owner's billing contact** (name, phone, GST) is personal data of the *customer*, not of workers. It lives in the **billing system** (separate, Phase 1: Razorpay/Zoho invoices handled by sales), not on the licence server.

### 5. Payments

In-app UPI renewal is **P1** (FR-LIC-07). Phase 1 renewals happen through sales, using a payment link (Razorpay) plus a key sent over WhatsApp/SMS.

## Options considered

| Option | Verdict |
|---|---|
| Plain JWT (RS256) | Rejected: alg-confusion pitfalls, larger keys; PASETO v4.public is simpler to use safely. |
| Online-only licence check | Rejected: TC-04. |
| Store billing via Google Play / App Store subscriptions | Rejected for Phase 1: direct B2B sales, sideload channel, 15–30% fees; revisit later. |
| Serverless (Lambda + DynamoDB) | Viable. A container chosen for simpler local dev and Postgres queries for support. |

## Consequences

- A determined attacker can patch the APK to skip checks. Integrity checks, server-side binding and the low price make that unattractive. We accept residual piracy (R-10).
- Sideload builds have weaker attestation and are tracked separately.
