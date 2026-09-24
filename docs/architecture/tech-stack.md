# Tech Stack

Every dependency here is justified, and the alternatives we rejected are listed. Adding a
dependency needs a line in this table and, if it's cross-cutting, an ADR.

## Platform and tooling

| Choice | Why | Alternatives rejected |
|---|---|---|
| **Flutter (stable) / Dart 3.9+** | One codebase for Android and iOS with native performance; web later | Native Kotlin + Swift (2× the cost); React Native (weaker for heavy pixel work) |
| **Dart pub workspaces** | Single lockfile, one resolution, fast `pub get` across 18 packages | Independent package lockfiles (version drift) |
| **melos 7** | Scripts across packages (`analyze`, `test`, `codegen`) | Makefiles (not cross-platform on Windows) |
| **very_good_analysis** | Strict lints; catches bugs in review | flutter_lints (too permissive for a team) |
| **mocktail** | Mocks without codegen | mockito (needs build_runner) |

## Application

| Choice | Why | Alternatives rejected |
|---|---|---|
| **flutter_riverpod 3** | Compile-safe DI + state; providers are overridable per app and in tests | Bloc (more boilerplate for DI); get_it (service locator, hides dependencies) |
| **go_router 18** | Declarative routes, deep links, `StatefulShellRoute` for tabs, web URLs | auto_route (codegen); Navigator 1 (no deep links) |
| **Drift + sqlite3** | Typed SQL, reactive streams (`watch`), migrations, testable in memory | sqflite (untyped, no streams); Isar/Hive (maintenance risk, weaker queries) |
| **path_provider** | App-private directories | — |

## Engines

| Capability | Choice | Why | Alternatives rejected |
|---|---|---|---|
| Document camera | **cunning_document_scanner** → ML Kit Document Scanner (Android), VisionKit `VNDocumentCameraViewController` (iOS) | Best-in-class edge detection and auto-capture, maintained by the platform vendors, no camera permission on Android | Custom CameraX + OpenCV (months of work; kept as the future path via `DocumentScanner` port); google_mlkit_document_scanner (Android only) |
| Fallback detection & warp | **engine_imaging** in pure Dart on `image` 4 | Works offline everywhere including web; deterministic, unit-testable | opencv_dart (heavy native binaries, +15–30 MB, build complexity); kept as a future adapter if accuracy demands it |
| Image codecs / filters | **image** 4 | Pure Dart, runs in isolates, JPEG/PNG/GIF/BMP/TIFF/WebP decode | flutter_image_compress (native, platform-specific behavior) |
| OCR | **google_mlkit_text_recognition** (bundled models) | On-device, fast, bundled Latin model works offline from first launch; Devanagari/CJK available | Tesseract (slower, larger, lower accuracy on phone photos); Apple Vision only (iOS only) |
| PDF writing | **pdf** 3 | Pure Dart, images + invisible text layer (`PdfTextRenderingMode.invisible`) for searchable PDFs | Native PdfDocument APIs (two implementations) |
| PDF render/text/manipulate | **pdfrx** 2 (PDFium) | Industry-standard renderer (Chrome's), text extraction, page assembly (`document.pages = …`, `encodePdf`) for merge/split/rotate, web support via WASM | PDFBox (JVM, Android only); syncfusion (commercial license) |
| OOXML (DOCX/XLSX/PPTX) | **archive** + **xml** in engine_conversion | Pure Dart, small, offline; enough for content-level conversions with honest fidelity | LibreOffice (not viable on mobile, see ADR-0007); docx_template (templating only) |
| Pickers | **image_picker** (Photo Picker / PHPicker), **file_picker** | Scoped access; no broad storage permission | Custom SAF integration |
| Share / save | **share_plus**, **file_picker `saveFile`** | OS share sheet; user-chosen destination | — |

## Docs, CI and delivery

| Choice | Why |
|---|---|
| **apps/docs** (Flutter web + flutter_markdown_plus) | Docs live next to the code, use the same design system, and are shipped as a container |
| **Docker** (`Dockerfile.docs`, `Dockerfile.ci`) | Reproducible docs hosting (nginx) and CI builds with the Android SDK |
| **GitHub Actions** | CI (format, analyze, test, build APK and web), GHCR docs image, tagged releases |
| **Dependabot** | Weekly pub, actions and docker updates |

## Deliberately excluded

- **google_fonts.** It downloads fonts at runtime and would break the offline promise. We use system fonts.
- **Analytics and crash SDKs.** None in v1 (privacy ADR-0008). If added later: opt-in, with no content.
- **Any HTTP client in feature or engine packages.**
