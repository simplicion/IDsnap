# ADR-0006: Write PDFs with `pdf`; render and manipulate with `pdfrx` (PDFium)

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
We need to create PDFs from images (with an optional text layer), render pages (thumbnails,
viewer, PDF → images, compression), extract text, and merge, split, reorder and rotate
existing PDFs, all offline on Android and iOS, with web possible later.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **pdf** (DavBfr) | Pure Dart, mature, invisible text rendering mode | Can't read existing PDFs |
| **pdfrx** (PDFium) | Chrome's renderer; text extraction; page assembly + `encodePdf`; iOS/Android/web | Native binary (~5 MB) |
| Syncfusion PDF | Feature-rich | Commercial license |
| PDFBox | Complete | JVM/Android only |

## Decision
`engine_pdf` implements the `PdfEngine` port. `fromImages` and `fromText` use `pdf`.
`pageCount`, `renderPage`, `extractText`, `merge`, `selectPages`, `rotatePages` and
`compress` use `pdfrx`. Every output is a **new** file that `CommitOutput` validates by
reopening it with PDFium.

## Consequences
- Compression re-renders pages as JPEG, so text stops being selectable. The UI says so (FR-14).
- Password-protected PDFs return `FailureCode.passwordProtected`. Unlocking comes later.
