# ADR-0005: Use ML Kit Text Recognition with bundled models for OCR

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
OCR must run on-device with no upload (FR-07, FR-11), work from first launch for English,
and support Hindi (Devanagari) for our core audience.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **google_mlkit_text_recognition** | Fast, accurate on phone photos, bundled models (`com.google.mlkit:text-recognition*`), line boxes | Mobile only; adds ~4 MB per script on Android |
| Tesseract (flutter_tesseract_ocr) | Many languages, cross-platform | Slower and less accurate on camera images; traineddata size |
| Apple Vision | Excellent on iOS | iOS only |

## Decision
Use a `TextRecognizer` port → `engine_ocr` adapter over ML Kit. **Latin is bundled** (the
default on both platforms). Devanagari, Chinese, Japanese and Korean are bundled on Android
through Gradle dependencies (see engine_ocr README); on iOS they need the matching
`GoogleMLKit/TextRecognition*` pods. `capability(script)` reports availability, and the UI
shows "Not installed" instead of failing silently.

## Consequences
- Searchable PDFs get an invisible text layer from OCR line boxes (Latin only in v1,
  because the embedded PDF font covers Latin-1).
- No OCR on web until a WASM engine is chosen (a future ADR).
- OCR text is never logged.
