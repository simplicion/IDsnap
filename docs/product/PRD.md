# Product Requirements Document — DocScan

| | |
|---|---|
| **Status** | Engineering baseline v1.1 |
| **Owner** | Principal Architect (see `.claude/skills/principal-architect`) |
| **Platforms** | Android and iOS (Flutter); web later |
| **Product type** | Offline-first document scanner, PDF toolkit, OCR and converter |
| **Last updated** | 2026-09-24 |

> **One-line promise:** Scan, organize and convert documents on your phone. No account. No upload. Core tools work offline.

This promise is enforced technically, not just in marketing. A feature is only described as
"works offline" after its runtime dependencies, models, fonts and processing path pass the
airplane-mode acceptance checklist in [Testing](../guides/testing.md).

---

## 1. Vision

Help people turn paper and files into clean, readable, searchable digital documents, and
convert supported formats, privately and reliably on their own device.

## 2. Problem

People regularly need to submit, archive, share or edit documents: exam forms, ID proofs,
receipts, signed contracts, class notes. Today's workflow is fragmented:

- Manual cropping and skewed, shadowed photos that upload portals reject.
- Accounts, cloud uploads and subscriptions gating basic features.
- A separate app for every task: one to compress, one to merge, one to make a passport
  photo, another to convert a Word file.
- File-size limits ("under 200 KB") that users can't hit without trial and error.

DocScan cuts the number of steps from paper (or a source file) to a usable output, while the
user keeps full control of sensitive files.

## 3. Users and jobs-to-be-done

| Persona | Everyday job | What "done" looks like |
|---|---|---|
| **Student** (Asha, 19) | Submit certificates and a passport photo to an admission portal | A 35 × 45 mm photo and a PDF under 500 KB, in 2 minutes |
| **Teacher** (Mr. Rao, 44) | Digitize worksheets; share notes with a class | A clean black-and-white multi-page PDF, shared to WhatsApp |
| **Office worker** (Priya, 31) | Scan a signed form; merge it with an annexure | One merged PDF with pages in the right order |
| **Small business** (Imran, 38) | Archive invoices and receipts | Named, foldered PDFs that are searchable by text |
| **Everyone** | Pull text from a photo of a notice or page | Copyable text, exportable as TXT or DOCX |

## 4. Product principles

1. **Local-first.** Capture, editing, OCR and supported conversions run on the device.
2. **Private by default.** No account, no automatic upload, no document content in telemetry.
3. **Honest fidelity.** Every conversion shows its fidelity class; we never claim a perfect conversion.
4. **Originals are preserved.** Edits are non-destructive until the user explicitly deletes the original.
5. **Simple first, powerful on demand.** Scanning is one tap; advanced tools live in Tools.
6. **Accessible and adaptive.** Screen readers, 200% text, dark mode, one-handed use.
7. **Resilient.** Long jobs survive navigation; drafts survive process death; failures leave inputs untouched.

## 5. Goals and non-goals

### Goals
- Produce clean, correctly oriented multi-page PDFs from the camera and gallery.
- Everyday tools in one app: crop presets, image compression to a target size, PDF merge,
  split, organize and compress, and PDF to images.
- On-device OCR with copy/export, plus searchable PDFs.
- A conversion registry that adds formats incrementally, each with a declared fidelity.
- Stay responsive on low-end Android devices.

### Non-goals (v1)
- Pixel-identical PDF → DOCX reconstruction.
- Legal certification, notarization or authentication of scans. **The app must never imply
  that a scan is equivalent to an official original.**
- Biometric compliance checks for passport photos (head size, background). We crop and size;
  the user verifies the official rules.
- Cloud sync, accounts, collaboration, server-side OCR.
- Handwriting, math notation, and rendering XLSX/PPTX with full layout.

## 6. Release scope

### P0 — Scanner and PDF MVP
- Platform document scanner (edge detection, auto-capture) and gallery import.
- Review: manual 4-corner crop with magnifier, rotate, filters (Original, Auto enhance,
  Grayscale, Black & white, Remove shadows), brightness and contrast.
- Page tray: reorder, rotate, delete, retake, add more.
- Save as PDF: name, page size (A4, Letter, Legal, Fit), quality (Small, Balanced, High).
- Library: search, sort, filter, folders, favorites, rename, delete with undo, share, save to device.
- Draft recovery after the app is killed.
- Light and dark themes, no-account onboarding.

### P1 — OCR and everyday tools
- OCR (Latin bundled; Devanagari, Chinese, Japanese and Korean where the model is available),
  with review/edit, copy, and export as TXT or DOCX.
- Searchable PDF (invisible text layer, Latin script) as a save option.
- PDF tools: merge, split/extract, organize (reorder, rotate, delete), compress, PDF → JPG/PNG.
- Image tools: **photo crop with presets** (passport 35×45 mm, US 2×2 in, China visa 33×48 mm,
  stamp 20×25 mm, ID card, A4, Letter, square, 4×6 in), **compress to a target size**
  (for example, 200 KB), resize, and JPG ↔ PNG.

### P2 — Conversions (pure Dart, offline)
See the matrix in §8. All run locally with no rendering server.

### P3 — Later
- Table/form reconstruction, handwriting, more OCR scripts, signatures and annotations,
  password protection, web app with a capability-specific feature set.

## 7. Functional requirements

| ID | Requirement | Acceptance |
|---|---|---|
| **FR-01 Capture** | Start a scan from Home in one tap. Use the platform scanner (ML Kit on Android, VisionKit on iOS). Allow gallery import. | Cancelling returns to Home without error. Captured originals are never silently discarded. |
| **FR-02 Detect & correct** | Detect page corners, apply perspective correction. Below confidence 0.6, show the corners for manual adjustment instead of cropping aggressively. | The crop editor always allows a reset to the full image. |
| **FR-03 Enhance** | Five filter presets plus brightness and contrast. Filters are parameters, not pixel edits. | Before/after comparison; reset restores the original. |
| **FR-04 Multi-page** | Thumbnails, page count, add, retake, rotate, reorder, delete. | The draft persists across app kill and restart. |
| **FR-05 PDF** | Build locally with page-size and quality presets. | The file is reopened with PDFium and its page count checked **before** success is shown. |
| **FR-06 Library** | List with name, type, date, size and pages. Search, sort, filter, folders, favorites, rename, move, delete (with undo), share, save to device. | Database rows and files stay consistent after every operation. |
| **FR-07 OCR** | On-device, script selectable, linked to its source, editable before export. | No network call. Confidence is shown as a hint, not a guarantee. |
| **FR-08 PDF tools** | Merge (user order), split by range, extract, reorder, rotate, delete, compress. | Always creates a new file; the source is never overwritten. |
| **FR-09 Conversion** | Each conversion declares its inputs, output, fidelity class, limitations and offline status. | Unsupported input shows a clear reason. Never "convert" by renaming an extension. |
| **FR-10 Share/export** | OS share sheet, "Save to device" (a destination the user picks), copy text. | The user is told that share targets may upload the file. |
| **FR-11 Privacy** | Scoped pickers, just-in-time permissions, app-private storage. | No document text, pixels, filenames or paths in logs or analytics (`RedactedLogger`). |
| **FR-12 Photo crop presets** | Fixed-aspect crop to preset mm sizes at 300 DPI (or custom). | Output pixel size matches the preset exactly. Copy says "check your country's official rules". |
| **FR-13 Compress to size** | JPEG quality search to fit a target (KB) while keeping the highest possible quality; optional max dimension. | Output ≤ target, or a clear message giving the smallest size achievable. |
| **FR-14 PDF compress honesty** | Compression re-renders pages as JPEG. | Before running, the UI warns that text will no longer be selectable, and shows the before/after size. |

## 8. Conversion matrix (implemented in `engine_conversion`)

Fidelity classes (from `FidelityClass` in `docscan_domain`):

- **Keeps appearance (visual).** Pages become images. Looks the same; text isn't editable.
- **Extracts content.** Text and data are kept; layout, fonts and images may change.
- **Rebuilds layout (reconstructed).** Structure is inferred; review before sharing.
- **Format-aware (native).** Uses a format-aware engine. Close, but not pixel-identical.

| Source | Output | Fidelity | Release | Notes |
|---|---|---|---:|---|
| JPG/PNG/WebP/BMP/GIF/TIFF (multi) | PDF | Visual | P0 | HEIC depends on the OS picker transcoding to JPEG |
| Camera scan | PDF / searchable PDF | Visual (+ text layer) | P0/P1 | Text layer is Latin-only in v1 |
| PDF | JPG / PNG (per page) | Visual | P1 | Rendered by PDFium |
| PDF (text-based) | TXT | Content | P1 | Scanned pages need OCR first |
| PDF | DOCX | Content | P2 | Paragraphs only; no layout reconstruction |
| Image (OCR) | TXT / DOCX | Content | P1 | Accuracy depends on image quality |
| Images | DOCX | Visual | P2 | One image per page; not editable text |
| TXT / Markdown | PDF | Content | P2 | Typeset with the bundled font |
| TXT | DOCX | Content | P2 | |
| CSV | PDF | Content | P2 | Monospace table |
| CSV | XLSX | Content | P2 | Values only, no formulas |
| XLSX | CSV | Content | P2 | First sheet, cached values |
| DOCX | TXT / PDF | Content | P2 | Formatting and images dropped |
| PPTX | TXT | Content | P2 | Slide text in order |
| HTML | TXT / PDF | Content | P2 | Tags stripped; no CSS layout |

**Not supported in v1** (and not advertised): XLSX/PPTX/DOCX → PDF *with layout*, DOC/XLS/PPT
legacy binaries, ODT/ODS, EPUB. The LibreOffice-class rendering these need is not viable
offline on mobile (see [ADR-0007](../adr/0007-pure-dart-ooxml-conversion.md)).

## 9. Offline guarantees

| Capability | Offline on first launch? | Caveat |
|---|---|---|
| Gallery import, crop, filters, PDF build, library, all PDF/image tools, conversions | ✅ Yes | None |
| Latin OCR | ✅ Yes | Model is bundled in the app |
| Devanagari/CJK OCR | ✅ Android (bundled); iOS depends on the pods included | Adds app size |
| Platform document scanner (Android) | ⚠️ Not guaranteed | ML Kit's scanner module is delivered by Google Play services and may download on first use. The app detects this, explains it, and offers gallery import with manual crop plus in-app edge detection as the offline fallback. |
| Platform document scanner (iOS) | ✅ Yes | VisionKit ships with the OS |

## 10. UX summary

Four tabs: **Home, Files, Tools, Settings**. See [DESIGN.md](../design/DESIGN.md) for every screen and state.

Core journeys:
1. Scan → review/crop → filter → reorder → name → Save PDF → share.
2. Tools → Passport photo → pick photo → choose preset → adjust → save.
3. Tools → Compress image → pick → "under 200 KB" → save.
4. Files → select 2 PDFs → Merge → reorder → save.
5. Tools → Extract text → pick image → review → copy/export.

## 11. Quality attributes

- **Performance budgets** (mid-tier Android, 2022): cold start < 1.5 s to an interactive Home;
  page render (2200 px, Balanced) < 1.2 s per page off the UI isolate; no frame over 32 ms
  while processing; 50-page PDF without out-of-memory on 3 GB RAM devices.
- **Reliability:** atomic commits (temp → validate → move); drafts survive process death;
  failures leave sources untouched.
- **Accessibility:** WCAG 2.2 AA contrast, 48 dp targets, 200% text without clipping,
  semantic labels, status never shown by color alone.
- **Compatibility:** Android 7.0+ (API 24; the ML Kit scanner needs API 21+ and Play services),
  iOS 15+.

## 12. Privacy and security

- App-private storage for drafts, originals and the library; `tmp/` is cleared after each job and at startup.
- No `INTERNET` permission is required by core features. Any future network feature needs an
  ADR, explicit consent, and an offline alternative.
- No analytics in v1. If added: opt-in and aggregate-only, never content, names or paths.
- Never claim legal certification.

## 13. Metrics (local or opt-in only)

Scan completion rate, export completion rate, conversion success by type (no content),
crash-free sessions, median processing time by device class.

## 14. Risks

| Risk | Mitigation |
|---|---|
| Edge detection fails on cluttered scenes | Confidence gating, manual corners, magnifier |
| ML Kit scanner unavailable offline or without Play services | Capability check + gallery/manual fallback |
| OCR is poor on low-quality photos | Capture guidance, filter before OCR, editable output |
| Users expect perfect PDF→DOCX | Fidelity labels, preview, honest copy |
| Memory pressure on large PDFs | Page-by-page rendering, isolates, quality presets |
| Plugin behavior differs by OS | Ports and adapters; real-device test matrix |

## 15. Definition of Done

A feature is done when: requirements and limitations are documented here; it's tested on
Android and iOS; offline behavior is verified; accessibility checks pass; unit, widget and
fixture tests pass; failure and cancel paths are tested; nothing sensitive is logged; output
files are validated by reopening them; performance is measured on a low-end device; and
product copy doesn't overstate accuracy, fidelity or legal standing.
