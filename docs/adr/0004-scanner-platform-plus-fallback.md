# ADR-0004: Use platform document scanners, with a pure-Dart fallback pipeline

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
Accurate edge detection, auto-capture and perspective correction are the core of the
product (PRD FR-01/02). Building a CameraX/AVFoundation camera with OpenCV detection is a
multi-month effort. The platforms already ship excellent scanners:
- **Android:** the ML Kit Document Scanner. Its UI and models come from **Google Play
  services** and may download on first use, so it is not guaranteed offline right after
  install, and it's unavailable on devices without Play services.
- **iOS:** VisionKit `VNDocumentCameraViewController`, bundled with the OS and fully offline.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **cunning_document_scanner** (wraps both) | One Dart API; best-in-class detection; no camera permission on Android | Play-services caveat; limited UI control |
| Custom camera + opencv_dart | Full control, fully offline | +15–30 MB; months of tuning |
| google_mlkit_document_scanner | Official plugin | Android only |

## Decision
- `DocumentScanner` port → `engine_scanner` adapter over `cunning_document_scanner`
  (`AndroidScannerMode.full`, gallery import allowed).
- `engine_imaging` provides a **pure-Dart fallback**: Otsu threshold + largest connected
  component + extreme-point quad, with a confidence score, perspective warp (homography +
  bilinear sampling), and filters. It's used for gallery imports and when the platform
  scanner is unavailable.
- Below confidence 0.6, the crop editor asks the user to confirm the corners.
- The capability is reported honestly via `EngineCapability.requiresDownload` on Android.

## Consequences
- The offline promise holds for iOS scanning and for every import + crop flow. Android
  camera scanning shows an explanation if the module isn't available yet.
- The `DocumentScanner` port leaves room for a future custom-camera adapter
  (CameraX + opencv_dart) without touching features.

## Validation
The fixture set in `apps/lab` measures detection success and mean corner error. Target:
≥ 90% detection on contrasting backgrounds, and corner error ≤ 2% of the diagonal.
