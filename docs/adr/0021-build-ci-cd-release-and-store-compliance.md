# ADR-0021: GitHub Actions + Fastlane, flavours, signing and store compliance

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product, Legal
- **Related:** NFR-OPS-01 · TC-07 · §13 Release plan · ADR-0003, ADR-0014, ADR-0017, ADR-0020

## Context

We ship to the **Play Store**, the **App Store** and a **sideload APK** for Android (NFR-OPS-01). Biometric-adjacent apps get extra scrutiny in store review. We need repeatable, signed builds, and clear environments for development, beta and production.

## Decision

### 1. Environments and flavours

| Flavour | Bundle / application ID | Licence server | Purpose |
|---|---|---|---|
| `dev` | `in.syncgate.app.dev` | `licence.dev.syncgate.in` | Engineers; debug tools; fake camera feed allowed |
| `staging` | `in.syncgate.app.staging` | `licence.staging.syncgate.in` | QA, internal testers, beta factories (M1–M2) |
| `prod` | `in.syncgate.app` | `licence.syncgate.in` | Customers |

(Domain names are placeholders until registered.)

Flavours are set with Android product flavours, iOS schemes/xcconfigs and `--dart-define-from-file=env/<flavour>.json`. Debug-only features (fake camera, threshold overlay) are **compiled out** of `prod`.

### 2. CI/CD pipeline (GitHub Actions)

| Workflow | Trigger | Steps |
|---|---|---|
| `pr.yml` | Pull request | `melos bootstrap` → format check → `flutter analyze` + import-boundary lint → unit/data/widget/golden tests → native unit tests (Linux for Kotlin, macOS for Swift) → MobSF + `osv-scanner` → outbound-schema check |
| `nightly.yml` | Schedule | Build dev/staging → Patrol on device lab / Firebase Test Lab → pipeline parity test → upload artefacts |
| `release.yml` | Tag `v*` | Build `prod` AAB + sideload APK + iOS IPA → sign → **Fastlane** upload: Play **internal** track, TestFlight → attach sideload APK + SHA-256 to the GitHub release (private) |
| `licence-server.yml` | Changes in `services/licence` | Go test + `govulncheck` → container build → deploy to staging → manual approval → prod |

- Versioning: `MAJOR.MINOR.PATCH+BUILD`; build number = CI run number.
- Flutter is pinned with **FVM**, and all dependencies are locked (`pubspec.lock` committed).
- Promotion: internal → closed beta (M2 factories) → production, with **staged rollout** (10% → 50% → 100%) on Play and phased release on the App Store.

### 3. Signing

- **iOS:** App Store distribution certificate and profiles managed by Fastlane **match** (encrypted private repo).
- **Android:** we keep **our own app signing key** (in a hardware-backed KMS / offline vault) and enrol it in **Play App Signing as an uploaded key**. Play builds and sideload APKs are then signed with the **same key**, so a sideloaded install can update to a Play install and back. A separate upload key is used for CI.
- Keys and secrets live in GitHub Actions encrypted secrets / OIDC → cloud KMS. Never in the repo.

### 4. Store compliance checklist (TC-07)

| Item | Android (Google Play) | iOS (App Store) |
|---|---|---|
| Privacy disclosures | **Data safety form**: data processed only on-device and never transmitted is *not "collected"* under Google's definition. We still declare optional crash diagnostics and the Google account used for Drive backup. Face data: "processed on device, not shared, not collected". | **App Privacy (nutrition labels)**: declare Diagnostics (opt-in, not linked to identity). No biometric data collected by the developer. |
| Permission strings | Camera rationale screen before the system prompt | `NSCameraUsageDescription`: "SyncGate uses the front camera to mark attendance by face. Faces are checked on this phone and never sent anywhere." Also `NSFaceIDUsageDescription` for admin unlock. |
| Biometric / face policies | Comply with the Play User Data policy; prominent disclosure + consent before enrolment (design 13) | Guideline 5.1.1 / 5.1.2: purpose-limited use of face data, no use for advertising or profiling, clear consent |
| Kiosk | Uses app pinning (no special permission). `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` justified in the review notes. | Guided Access is user-initiated. Review notes explain the kiosk use. |
| Account deletion | Not applicable (no user accounts with us). The owner can delete all data in-app. | Same: the "Delete all data" flow is documented in the review notes. |
| Review access | Demo licence key + test video for reviewers | Same |
| Export compliance | Standard encryption (exempt under the category-5 mass-market note); `ITSAppUsesNonExemptEncryption = NO` after confirmation | |

### 5. Sideload APK channel

- Distributed through the SyncGate website and local resellers, for phones without Play access or for faster updates during beta.
- The app checks for updates via the licence server (`/v1/check-update`: latest version + SHA-256) and offers a download through the system installer. It **never** self-installs silently.

## Consequences

- One app signing key for both Android channels must be protected as a critical secret. Losing it means users cannot update.
- iOS builds need macOS runners, which cost more. iOS CI runs only on PRs that touch iOS or shared code, and nightly.
