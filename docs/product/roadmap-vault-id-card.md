# Roadmap: ID Card Front & Back, Document Vault, Application Kits

**Status:** Approved design, not yet implemented · **Owner:** Principal Architect
**Depends on:** P0/P1 engines (scan, imaging, PDF, OCR, face framing) — all shipped.

This plan turns DocScan from a utility you open once into the place people
keep their important documents. It covers four product shifts, the order to
build them, and exactly what changes in each package.

---

## 1. Decision: what to build first

| Order | Feature | Why this position |
|---|---|---|
| **1** | **ID Card Front & Back on one page** | Highest-frequency real task (banks, hotels, HR, rentals). ~95 % reuse of shipped engines. No security risk. Ships in about a week and immediately makes the app worth keeping. |
| **2** | **Vault categories + App Lock** | The retention hook. Needs care: an app lock is an *access gate*, not encryption. We ship the lock honestly first, then add encryption at rest behind its own ADR. |
| **3** | **Application Kits (Visa / Exam / Job presets)** | Composes crop + compress + scan into one guided flow. Builds on 1 and on the vault's categories. |
| **4** | **Data Independence export + privacy banner** | Small, but completes the trust story. Can ship alongside 2. |

**Why ID Card before Vault:** the vault is only valuable once it contains
documents. The ID Card flow is the fastest way to get a user's *most
important* documents (ID, licence) into the app — and it lands them straight
into the right vault category once 2 ships.

---

## 2. Feature A — ID Card: Front & Back on One Page

### User story
> "The bank wants my Aadhaar / driving licence front and back on one page."

### Flow

```
Home ▸ "ID card (front & back)"
 ┌──────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────┐
 │  Step 1 of 2 · FRONT     │   │  Step 2 of 2 · BACK      │   │  Preview (A4)            │
 │  ┌────────────────────┐  │   │  ┌────────────────────┐  │   │  ┌────────────────────┐  │
 │  │  [ card outline ]  │  │   │  │  [ card outline ]  │  │   │  │  ┌──────────────┐  │  │
 │  └────────────────────┘  │ ▶ │  └────────────────────┘  │ ▶ │  │  │    FRONT     │  │  │
 │  Place the front of the  │   │  Now flip the card over  │   │  │  └──────────────┘  │  │
 │  card inside the frame   │   │                          │   │  │  ┌──────────────┐  │  │
 │  [ Scan ]  [ From photos]│   │  [ Scan ]  [ From photos]│   │  │  │    BACK      │  │  │
 └──────────────────────────┘   └──────────────────────────┘   │  │  └──────────────┘  │  │
                                                               │  └────────────────────┘  │
                                                               │ Layout: ● Stacked ○ Side │
                                                               │ Size:   ● Actual  ○ Fit  │
                                                               │ ☐ Add "Copy" watermark   │
                                                               │ [ Retake front ][ back ] │
                                                               │ [      Save PDF       ]  │
                                                               └──────────────────────────┘
```

### Behaviour
- **Capture:** the platform scanner (`DocumentScanner.scan(maxPages: 1)`) for each side;
  gallery import falls back to `ImageProcessor.detectDocument` + manual corners (existing crop screen).
- **Straighten:** existing `renderPage` with the detected quad, filter `enhanced`.
- **Card normalisation:** the output is forced to the ISO/IEC 7810 ID-1 aspect (85.6 × 53.98 mm).
  If the detected aspect is off by more than 8 %, show "Check corners" (the same pattern as the scan review).
- **Layout (new pure function):** `composeIdCardSheet(front, back, layout, sizing)`, which places both
  images on an A4 page:
  - *Actual size* (default): each card is printed at 85.6 × 53.98 mm, so photocopies look real-size.
  - *Fit*: each card is scaled to 80 % of the page width.
  - *Stacked* (default) or *Side by side* (landscape A4).
  - Thin 0.5 pt grey border, 12 mm gap, centered.
- **Optional watermark:** "COPY — for <purpose> only", drawn diagonally at 12 % opacity. The user enters the
  purpose. This is a common, legitimate anti-misuse practice for ID copies.
- **Output:** one validated PDF through `CommitOutput`, suggested name "ID card — <date>". Once
  Feature B ships it's filed in **IDs & Proofs**.
- **Honesty:** the copy says "Copy of your card" — never "certified" or "official".

### Engineering
| Package | Change |
|---|---|
| `docscan_domain` | `IdCardLayout` / `IdCardSizing` enums; `IdCardSheet` value object; use case `ComposeIdCardPdf` (renders both sides → `PdfEngine.fromPlacedImages`). |
| `docscan_domain` ports | `PdfEngine.fromPlacedImages(List<PlacedImage>, PdfPageSize, {String? watermark})`: positioned images in points. |
| `engine_pdf` | Implement `fromPlacedImages` with `package:pdf` (pure data into `Isolate.run`: bytes + rects only). |
| `feature_scan` | New route `/scan/id-card` with a 3-step screen (`IdCardFlowController`, a Notifier persisted to `DraftStore` under a separate key so a half-done flow survives process death). |
| `feature_home` | Quick action "ID card (front & back)". |
| `docscan_contracts` | `Routes.idCard`. |

**Tests:** layout math (actual size = 242.6 × 153.0 pt, centred, no overlap, both layouts); the
aspect warning threshold; controller persistence; widget flow with fakes; on-device integration
test (two synthetic card images → a 1-page PDF with the right dimensions).

**Estimate:** 4–6 dev-days including tests.

---

## 3. Feature B — Document Vault (categories + App Lock)

### B1. Smart categories
Replace the flat "Files" root with a **Vault** home, keeping plain folders for everything else.

| Category | Suggested items (empty-state prompts) |
|---|---|
| IDs & Proofs | National ID, Passport, Driving licence, Voter ID, PAN / tax ID |
| Education & Career | Degree, Marksheets, Certificates, Resume, Offer letters |
| Medical & Health | Prescriptions, Reports, Insurance card, Vaccination record |
| Vehicles & Insurance | RC / registration, Insurance policy, PUC, Service records |
| Tax & Receipts | Tax returns, Salary slips, Rent receipts, Bills |
| Home & Legal | Rent agreement, Property papers, Utility bills |

- Empty-state "slots" ("Tap to add your Passport") start the right flow: the passport slot opens a
  2-page scan, the ID slots open the ID Card flow, the others open a normal scan.
- Documents can carry a category plus an optional **expiry date**, used for local reminders in B4.
- Categories are **system folders**: fixed IDs, renamable labels, can't be deleted, hidden when empty
  (setting).

**Data model (Drift migration v1 → v2):**
```
documents: + category TEXT NULL, + expires_at INTEGER NULL, + slot TEXT NULL
folders:   + system_key TEXT NULL UNIQUE
```
The migration is additive only. It has a test against a v1 fixture database.

### B2. App Lock (biometric / device credential)
- Package: `local_auth` (Android BiometricPrompt, iOS LocalAuthentication). There's **no network** and
  no new dangerous permission; Android adds only `USE_BIOMETRIC`.
- `MainActivity` must extend `FlutterFragmentActivity` (a `local_auth` requirement).
- Behaviour: when the lock is on, it triggers at cold start and after N minutes in the background
  (setting: immediately, 1 min or 5 min). While locked, the app shows a privacy screen, and the
  Android `FLAG_SECURE` flag / iOS snapshot blur hide content in the app switcher.
- Fallback: the device PIN, pattern or password through the system prompt. DocScan does **not** keep
  its own PIN in v1, because that would add a recovery problem and a weak secret.
- A new domain port `AppLock` { `capability()`, `authenticate(reason)` } in `engine_security`.
- **Honest copy:** "App Lock keeps other people out of DocScan on this phone." We **don't** say
  "bank-grade" or "encrypted" until B3 ships.

### B3. Encryption at rest (separate ADR required before building)
- Encrypt vault files with AES-256-GCM, using per-file keys wrapped by a master key in the Android
  Keystore / iOS Keychain (`flutter_secure_storage`). Encrypt the database with SQLCipher
  (`sqlcipher_flutter_libs`).
- Trade-offs to settle in the ADR:
  - **Backup/restore:** device-bound keys mean an OS backup can't be restored to a new phone. The
    answer is the Data Independence export (B4), made **before** a device change.
  - **Performance:** streaming encryption for large PDFs.
  - **Sharing:** decrypt to a temp file, shred it after the share sheet closes.
- Marketing may claim "encrypted" only after B3 passes a security review.

### B4. Data Independence export + expiry reminders
- **Export all:** a ZIP (`archive`) with category folders and original file names, plus
  `manifest.json` (names, categories, dates), saved via `ShareService.saveToDevice`. With B3 in
  place, the export is decrypted, behind an explicit warning and re-authentication.
- **Import ZIP:** restores the same structure. It's validated through `CommitOutput`.
- **Expiry reminders** use local notifications only (`flutter_local_notifications`), scheduled on
  the device, 30 days and 7 days before expiry.

### B5. Privacy banner
A slim, dismissible (per session) banner on Home and Vault: **"Offline vault · Nothing leaves this
phone"**. The claim is true because release builds have no INTERNET permission (ADR-0008), so the
claim is enforced by the OS.

**Estimate:**
| Part | Dev-days |
|---|---|
| B1 | 5–7 |
| B2 | 3–4 |
| B3 | 8–12, plus a security review |
| B4 | 4–5 |
| B5 | 0.5 |

---

## 4. Feature C — Application Kits (portal-ready outputs)

**Framing:** a kit bundles *published* constraints so users don't have to learn them. We never
promise that a portal will accept an upload. Every kit shows "Check the latest official
requirements" and its **source + last-reviewed date**.

| Kit | Outputs (each committed and validated) |
|---|---|
| **US Visa / Green Card photo** | 2 × 2 in JPEG, 600–1200 px square, **≤ 240 KB**, head 50–69 % (auto-framed) |
| **Schengen visa photo** | 35 × 45 mm, head 70–80 %, light-background *hint* |
| **Exam / college portal** | Photo ≤ 50 KB (JPEG), signature ≤ 20 KB (crop + B&W + compress), documents PDF ≤ 300 KB |
| **Job application** | Resume/certificates merged PDF ≤ 2 MB, photo ≤ 100 KB |
| **Custom kit** | The user sets size, dimensions and format limits and saves them as a reusable kit |

**Engineering:**
- **Domain:** `ApplicationKit` { id, label, source, reviewedOn, `List<KitItem>` } with a sealed
  `KitItem`:
  - `PhotoItem(CropPreset, maxBytes)`
  - `SignatureItem(maxBytes, size)`
  - `DocumentItem(maxBytes, pageSize)`
- Kits are **data** (a versioned JSON asset), so requirement updates ship without code changes.
- **Signature cleanup:** a new `EnhancementFilter.signature` (threshold with a transparent or white
  background, tight auto-crop to the ink bounding box). It's pure Dart in `engine_imaging`.
- **Size enforcement:** photos reuse `compress(targetBytes)`. PDFs try, in order:
  - `PdfCompressionLevel` steps, then
  - a lower render DPI, then
  - if still over the limit, a clear message: "Can't reach 300 KB without making text unreadable.
    Try fewer pages."
- The "Kit result" screen shows every item with a ✅ size/dimension check and "Save all to Vault ›
  <category>".
- **Background check (hint only):** measure how uniform the border region is. If variance is high,
  warn "Background may not be plain". No ML segmentation in v1.

**Estimate:** 6–8 dev-days.

---

## 5. Cross-cutting requirements
- **Offline:** every new feature must pass the airplane-mode checklist (guides/testing.md). No new
  INTERNET permission, and the manifest is audited in CI (a new CI step greps the merged release
  manifest).
- **Isolates:** only pure data (bytes, numbers, enums) may cross into `Isolate.run`, never closures
  that capture UI callbacks. This is enforced by the lint `test/isolate_boundary_test.dart` pattern
  introduced in the 2026-09 production fix.
- **Typed failures:** new `FailureCode`s (`biometricUnavailable`, `lockedOut`,
  `targetSizeUnreachable`) with a title, a recovery hint and an action.
- **Accessibility:**
  - Every step is announced ("Step 1 of 2, front of card").
  - The camera flows have non-camera alternatives.
  - The lock screen works with TalkBack/VoiceOver.
- **Tests:** unit tests for layout, kit constraints and migrations; widget tests for each flow; and
  on-device `integration_test` for ID Card, lock and kits on the emulator in CI.

## 6. Release plan
| Release | Contents | Gate |
|---|---|---|
| 1.1 | ID Card flow + privacy banner | On-device tests green; manual QA on 2 Android + 1 iOS device |
| 1.2 | Vault categories + App Lock + Export | Migration tested on real v1 data; lock-bypass QA |
| 1.3 | Application Kits | Kit sources reviewed and dated |
| 1.4 | Encryption at rest | ADR approved + security review |

## 7. Explicit non-goals
- Claims of legal validity, notarisation or guaranteed portal acceptance.
- Cloud backup or sync (the user-controlled export covers this).
- A custom in-app PIN in v1. We use the device credential instead.
