# Testing Strategy

We test at the lowest layer that can prove the behavior. Most logic is pure Dart and is
tested without a device.

## Test pyramid

| Layer | Where | What | Tooling |
|---|---|---|---|
| Unit | `packages/core`, `domain`, `engines/imaging`, `engines/conversion` | Result/failures, format sniffing, geometry, homography, filters, detection on synthetic images, crop presets, compression to target size, OOXML read/write, conversion registry | `package:test`, mocktail |
| Adapter | `packages/data`, `engines/pdf` | Drift queries against an in-memory DB; PDF build → reopen → page count; merge/split/rotate | `flutter_test`, `NativeDatabase.memory()`, pdfrx |
| Widget | `packages/features/*`, `design_system`, `apps/docs` | Screen states (empty/loading/error/success), navigation, a11y labels | `flutter_test`, `ProviderScope` overrides with fakes |
| Integration | `apps/scanner/integration_test` | Scan (gallery import) → save → library → share, on real devices | `integration_test` |
| Fixture/benchmark | `apps/lab` | Detection accuracy, render time, output size on the fixture corpus | Lab app |

Rules:
- Every bug fix adds a test that fails before the fix.
- Engines never need a device for unit tests. Platform plugins sit behind ports and are faked in feature tests.
- Output validation is tested: corrupt bytes must yield `outputValidationFailed` and leave no file behind.

## Fixture corpus (consented, non-sensitive)

Kept in `apps/lab/assets/fixtures/` (synthetic or self-made only):
- Flat, angled (15°/30°/45°), shadowed, low-light, glossy, folded and low-contrast pages.
- Small print, tables, forms, stamps, signatures, mixed English and Hindi text.
- Receipts (narrow and long), ID-card-sized cards, passport-style portraits.
- Text PDFs, image-only PDFs, encrypted PDFs, a 100-page PDF, a corrupt PDF.
- DOCX/XLSX/PPTX/CSV/HTML/MD samples, including empty and malformed ones.

Metrics tracked: detection success rate, mean corner error (% of the diagonal), OCR CER/WER
on the reference text, ms/page, peak memory, output size, crash count.

## Airplane-mode acceptance checklist (release gate)

With airplane mode **on**, Wi-Fi **off**, on a freshly installed build:

- [ ] App launches; Home, Files, Tools and Settings render.
- [ ] Import photos → crop → filter → Save PDF → opens in the viewer.
- [ ] Scan with the camera (iOS VisionKit). On Android, if the ML Kit module isn't
      downloaded, the explanation and fallback appear. No crash.
- [ ] Extract text from an English image (bundled Latin model).
- [ ] Searchable PDF: text is selectable/searchable in another PDF viewer.
- [ ] Merge, split, organize and compress PDFs; PDF → JPG.
- [ ] Passport crop (35×45 mm) outputs 413 × 531 px.
- [ ] Compress an image to under 200 KB.
- [ ] Every conversion in the registry completes on its sample fixture.
- [ ] Rename, move, favorite, delete + undo, share sheet opens.
- [ ] Kill the app mid-scan; relaunch; the draft banner appears with all pages.
- [ ] A proxy (e.g. mitmproxy with airplane mode off) shows **zero** requests from core flows.

## Device matrix

| Tier | Android | iOS |
|---|---|---|
| Low | 3 GB RAM, Android 9–10 (e.g. Redmi 9A, Galaxy A10) | iPhone SE 2nd gen, iOS 16 |
| Mid | 6 GB RAM, Android 13 (e.g. Galaxy A54, Pixel 6a) | iPhone 12, iOS 17 |
| High | Pixel 9 / Galaxy S24, Android 15–16 | iPhone 16, iOS 18+ |
| Special | Device without Google Play (e.g. Huawei) → scanner fallback | iPad (tablet layout) |

## CI

`.github/workflows/ci.yml` runs format check, analyze (`--fatal-infos`), codegen, all
package tests, the web docs build and an Android debug APK build on every push and PR.
