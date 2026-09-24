# ADR-0007: Pure-Dart content conversions with declared fidelity; no LibreOffice on mobile

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
Users want "convert anything to anything". High-fidelity Office → PDF rendering needs a full
layout engine (LibreOffice, Office, or a commercial SDK). On mobile:
- LibreOffice builds add 100–200 MB. The Android port is unmaintained for embedding, there's
  no supported iOS embedding, and it's MPL/LGPL, which raises compliance work.
- Commercial SDKs (Aspose, Syncfusion, Apryse) cost money per developer or per app, and some
  phone home for licensing.
- A server would break the privacy and offline promise.

## Decision
Implement conversions in `engine_conversion` with `archive` + `xml` (DOCX/XLSX/PPTX are ZIP
+ XML) and the `PdfEngine`/`ImageProcessor` ports. Every conversion is a registered
`ConversionSpec` with a `FidelityClass`:

- **visual:** images ↔ PDF, images → DOCX (image per page), PDF → images.
- **content:** DOCX → TXT/PDF, PDF → TXT/DOCX, TXT/MD/HTML → PDF, TXT → DOCX, CSV ↔ XLSX,
  XLSX → CSV, PPTX → TXT, HTML → TXT, OCR → TXT/DOCX.

Layout-preserving Office → PDF is **not offered** in v1, rather than offered badly.

## Consequences
- The UI shows each spec's fidelity and limitations before running it.
- If demand is proven, a future ADR can evaluate an optional commercial on-device SDK behind
  the same `ConversionEngine` port.
