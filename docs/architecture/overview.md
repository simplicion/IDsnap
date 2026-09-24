# Architecture Overview

DocScan is a **modular, ports-and-adapters Flutter monorepo**. The product logic is pure Dart
and doesn't depend on Flutter, plugins or `dart:io`. Platform capabilities (camera, OCR,
PDFium, SQLite, file system) sit behind interfaces ("ports") and are wired together in one
place per app. This lets us test the core without devices, swap engines without touching
features, and later ship a web build with a different set of adapters.

## 1. Monorepo map

```
docscan/
├── apps/
│   ├── scanner/          The product: Android + iOS. Composition root only.
│   ├── docs/             Flutter web app that renders /docs (this site).
│   └── lab/              Engine lab: run imaging/PDF pipelines on fixtures, benchmark.
├── packages/
│   ├── core/             docscan_core: Result, AppFailure/FailureCode, ids,
│   │                     RedactedLogger, DocumentFormat sniffing, runHeavy.  (pure Dart)
│   ├── domain/           docscan_domain: entities, PORTS, use cases.          (pure Dart)
│   ├── contracts/        docscan_contracts: Riverpod providers per port,
│   │                     settings controller, Routes (navigation contract).
│   ├── design_system/    docscan_design_system: tokens, themes, widgets.
│   ├── data/             docscan_data: Drift DB, FileStore, DraftStore, SettingsStore.
│   ├── engines/
│   │   ├── imaging/      engine_imaging: detection, perspective warp, filters,
│   │   │                 crop/compress.                                        (pure Dart)
│   │   ├── pdf/          engine_pdf: `pdf` writer + `pdfrx` (PDFium) render/manipulate.
│   │   ├── ocr/          engine_ocr: ML Kit Text Recognition (on-device).
│   │   ├── vision/       engine_vision: ML Kit face detection (bundled) for passport auto-framing.
│   │   ├── scanner/      engine_scanner: platform scanner, pickers, share.
│   │   └── conversion/   engine_conversion: registry + pure-Dart OOXML/text converters.
│   └── features/
│       ├── home/  scan/  library/  tools/  settings/   Vertical UI slices.
├── docs/                 Product, design, architecture, ADRs, guides (source of truth).
├── tool/                 Repo scripts (docs sync, docker config).
└── .github/              CI, docs image publishing, releases.
```

Dependencies are resolved as a single **Dart pub workspace** (`workspace:` in the root
`pubspec.yaml`, `resolution: workspace` in every member), so there is one lockfile and one
version of every dependency. Melos provides the scripts (`analyze`, `test`, `codegen`,
`format:check`, `run:*`).

## 2. Dependency rules

```
                 ┌──────────────┐
                 │  apps/*      │  wires adapters → ports (ProviderScope overrides)
                 └──────┬───────┘
        ┌───────────────┼────────────────────────────┐
        ▼               ▼                            ▼
 ┌─────────────┐  ┌─────────────┐             ┌─────────────┐
 │ features/*  │  │ data        │             │ engines/*   │
 └──┬───┬───┬──┘  └──────┬──────┘             └──────┬──────┘
    │   │   │            │ implements ports          │ implements ports
    │   │   ▼            ▼                           ▼
    │   │  ┌────────────────────────────────────────────────┐
    │   └─►│ docscan_contracts (providers, Routes, settings)│
    │      └──────────────────────┬─────────────────────────┘
    ▼                             ▼
 ┌──────────────────┐   ┌──────────────────────────────────┐
 │ design_system    │   │ docscan_domain (entities, ports, │
 └────────┬─────────┘   │ use cases)                       │
          │             └───────────────┬──────────────────┘
          └────────────►┌───────────────▼──────────────────┐
                        │ docscan_core                     │
                        └──────────────────────────────────┘
```

Rules (a violation fails review):

1. `core` depends on nothing internal. `domain` depends only on `core`.
2. **Ports live in `docscan_domain`** (`lib/src/ports/`). Engines and `data` implement them.
3. `features/*` depend on `domain`, `contracts` and `design_system`. They **never** import
   another feature, `data`, or a concrete engine.
4. Only `apps/*` import concrete adapters and override the providers in `docscan_contracts`.
5. Cross-feature navigation goes through `Routes` (for example,
   `Routes.tool(ToolId.merge, docId: id)`), never through another feature's widgets.
6. No `dart:io` in `core`, `domain`, `engine_imaging` or the conversion registry, to keep them web-ready.

## 3. Layers inside a feature

```
features/tools/lib/src/
  compress_image/
    compress_image_screen.dart      presentation (widgets)
    compress_image_controller.dart  application state (Notifier) → calls ports/use cases
```

Controllers are Riverpod `Notifier`/`AsyncNotifier`s. They read ports through providers
(`ref.read(imageProcessorProvider)`), and they hold no platform code.

## 4. Key flows

### 4.1 Scan → PDF

```
Home ──Routes.scan()──► ScanController
   │ DocumentScanner.scan()           (ML Kit / VisionKit, returns image paths)
   │ FileStore.importOriginal(path)   (copied into originals/, never modified)
   │ ImageProcessor.detectDocument()  (only for gallery imports; platform scans are pre-cropped)
   │ DraftStore.save(draft)           (after every change → survives process death)
   ▼
Review/Crop/Filter: edits are PageEdits parameters (quad, quarterTurns, filter, brightness, contrast)
   ▼
SaveScanAsPdf (use case, docscan_domain)
   for each page:  read original → ImageProcessor.renderPage(edits, preset)  [isolate]
                   (optional) TextRecognizer.recognize(rendered) → text layer
   PdfEngine.fromImages(pages, options, textLayers)
   CommitOutput(OutputFile(expectedPages: n))
   ▼
DraftStore.clear() → success sheet (only now)
```

### 4.2 Commit pipeline (`CommitOutput`, the only way files enter the library)

```
bytes ─► FileStore.writeTemp()  ─► validate ─► FileStore.commit()  ─► thumbnail ─► DocumentRepository.add()
                                   │ PDF: PDFium reopens, page count == expected
                                   │ JPG/PNG: decodes
                                   │ DOCX/XLSX: ZIP signature
                                   │ text: valid UTF-8
                                   └─ fail → delete temp, Err(outputValidationFailed)
If the DB insert fails, the committed file and thumbnail are deleted (no orphans).
```

### 4.3 OCR

`TextRecognizer.recognize(imagePath, script)` → `OcrResult` (blocks → lines with normalized
boxes). For PDFs, embedded text is tried first (`PdfEngine.extractText`). Only pages without
text are rendered (`renderPage`) and OCR'd.

### 4.4 Conversion

`ConversionEngine` (engine_conversion) holds a registry of `ConversionSpec`s: inputs, output,
`FidelityClass`, limitations. The Tools UI is generated from the registry, so a spec that
isn't registered can't appear. `convert(request)` returns `OutputFile`s, which go through
`CommitOutput` like everything else.

## 5. Threading

- Pixel work (decode, warp, filters, encode, detection) runs through `runHeavy()` from
  `docscan_core`. That's `Isolate.run` on mobile and desktop, and inline on web.
- PDFium (pdfrx) and ML Kit run on native threads.
- Controllers `await` results. The UI thread only paints.
- Large documents are processed page by page. Only the current page's full-resolution
  pixels are in memory.

## 6. Storage layout (app-private)

```
<app documents dir>/docscan/
  documents/   committed library files (<uuid>.<ext>); display names live in the DB
  originals/   untouched captured/imported images for drafts
  thumbs/      360 px JPEG thumbnails (<documentId>.jpg)
  tmp/         work in progress; cleared at startup and after jobs
  drafts/      draft.json (current ScanDraft)
  docscan.sqlite  Drift database: documents, folders
  settings.json
```

Paths stored in the DB are **relative** to this root, so backups and restores stay valid.

## 7. Error model

Every port returns `Result<T>` (`Ok` / `Err(AppFailure)`); nothing throws across a package
boundary. `FailureCode` carries the user-facing title and recovery hint:

`permissionDenied`, `cameraUnavailable`, `captureCancelled`, `documentNotDetected`,
`lowImageQuality`, `unsupportedFormat`, `corruptFile`, `passwordProtected`,
`modelUnavailable`, `offlineDependencyUnavailable`, `insufficientStorage`,
`memoryLimitExceeded`, `processingCancelled`, `conversionFailed`,
`outputValidationFailed`, `notFound`, `unknown`.

`AppFailure.toString()` prints only the code, because `cause` may contain paths or content.
Logging uses `RedactedLogger`, which drops any string that looks like a path or is longer
than 64 characters.

## 8. Web readiness

The pure packages already compile for web. A future `apps/web` would supply web adapters:
browser file input, IndexedDB `FileStore`, `pdfrx` (which supports web through PDFium WASM),
and no ML Kit (OCR disabled or a WASM engine). The capability model (`EngineCapability`)
hides what isn't available instead of failing at runtime.

## Automatic passport / ID photo framing

`FaceLocator` (domain port, implemented by `engine_vision` with ML Kit's bundled
face-detection model) finds the largest face. The pure function
`autoFramePortrait` (docscan_domain) then sizes the crop so the head
(chin to crown ≈ 1.3 × the detector box) fills the preset's `headRatio`
(e.g. 75 % for 35 × 45 mm, 60 % for US 2 × 2 in), centers it horizontally and
leaves `topMarginRatio` above the crown. The user can fine-tune by pinch/drag.
DocScan never claims official compliance; the tool shows a disclaimer.

## Release permissions (verified)

The merged release manifest requests **no** dangerous or network permissions:
`INTERNET` and `ACCESS_NETWORK_STATE` are removed with `tools:node="remove"`.
The platform document scanner runs inside Google Play services (its own
process), and gallery/file access uses the system photo & document pickers.
