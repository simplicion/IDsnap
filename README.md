# DocScan

**Scan, organize and convert documents on your phone. No account. No upload. Core tools work offline.**

<!-- Replace OWNER/REPO once the GitHub repository exists -->
[![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)
[![Docs image](https://github.com/OWNER/REPO/actions/workflows/docs.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/docs.yml)

DocScan turns paper into clean, searchable PDFs and bundles the everyday document tools
people usually need five apps for: passport-photo crops, "compress under 200 KB", merging,
splitting and converting. Everything runs on the device. It's built with Flutter for Android
and iOS, with web planned.

## Features

| Area | What you can do |
|---|---|
| **Scan** | Platform document camera (ML Kit / VisionKit) with edge detection and auto-capture · gallery import · 4-corner crop with magnifier · 5 filters (Auto enhance, Grayscale, B&W, Remove shadows, Original) · brightness/contrast · multi-page reorder/rotate/retake · draft recovery |
| **PDF** | Images → PDF (A4/Letter/Legal/Fit, 3 quality presets) · searchable PDF (OCR text layer) · merge · split/extract · organize (reorder, rotate, delete) · compress · PDF → JPG/PNG |
| **Image** | Photo crop presets: passport 35×45 mm, US 2×2 in, China visa, stamp size, ID card, A4, Letter, square, 4×6 · compress to a target size · resize · JPG ↔ PNG |
| **Text (OCR)** | On-device text recognition (Latin bundled; Devanagari/CJK), edit, copy, export TXT/DOCX |
| **Convert** | DOCX ↔ TXT/PDF, PDF → TXT/DOCX, TXT/MD/HTML → PDF, CSV ↔ XLSX, XLSX → CSV, PPTX → TXT, images → DOCX. Each one shows an honest fidelity label |
| **Files** | Search, sort, filters, folders, favorites, rename, delete with undo, share, save to device |
| **Comfort** | Light & dark themes, 200% text support, screen-reader labels, no account, no ads in core flows |

> Scans are copies, not certified originals. Conversions state their fidelity; layout-perfect
> Office rendering is intentionally not offered offline (see ADR-0007).

## Screenshots

_Coming soon: Home · Review · Passport crop · Files (light & dark)._

## Monorepo

```
apps/
  scanner/        Android + iOS product app (composition root)
  docs/           Documentation site (Flutter web) rendering /docs
  lab/            Engine lab for fixtures and benchmarks
packages/
  core/           Result, failures, logging, format sniffing (pure Dart)
  domain/         Entities, ports, use cases (pure Dart)
  contracts/      Riverpod providers for ports, settings, route contract
  design_system/  Tokens, light/dark themes, components
  data/           Drift DB + file/draft/settings stores
  engines/        imaging · pdf · ocr · scanner · conversion
  features/       home · scan · library · tools · settings
docs/             PRD, DESIGN, architecture, ADRs, guides
tool/             Scripts (docs sync, CI, docker config)
```

Architecture: [docs/architecture/overview.md](docs/architecture/overview.md) ·
Design: [docs/design/DESIGN.md](docs/design/DESIGN.md) ·
Product: [docs/product/PRD.md](docs/product/PRD.md)

## Quick start

```bash
flutter pub get                      # whole workspace, one lockfile
dart run melos run codegen           # Drift code generation
dart run melos run analyze
dart run melos run test

cd apps/scanner && flutter run       # device/emulator
```

Melos scripts: `analyze`, `format`, `format:check`, `test`, `codegen`, `run:scanner`, `run:docs`, `run:lab`.

## Documentation app

```bash
dart run tool/sync_docs.dart         # copy /docs into apps/docs/assets
cd apps/docs && flutter run -d chrome
```

## Docker

```bash
docker compose up --build docs                  # docs at http://localhost:8080
docker compose --profile ci run --rm ci         # full CI in a container; APK → ./out
docker build -f Dockerfile.docs -t docscan-docs .
```

GitHub Actions: `ci.yml` (format, analyze, test, docs web, debug APK), `docs.yml` (publishes
`ghcr.io/<owner>/<repo>/docs`), `release.yml` (tags `v*` → APK/AAB on a GitHub Release).

## Privacy promise

- No account and no document upload. Core features need no network.
- No analytics or crash SDKs. Nothing sensitive is logged.
- Sharing happens only when you tap Share, and the target app handles your file under its own policy.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [Contributing a Tool](docs/guides/contributing-a-tool.md).

## License

TBD. No license has been chosen yet; all rights reserved until one is added.
