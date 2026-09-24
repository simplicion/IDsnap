# Architecture & Code Review Checklist

## 1. Correctness and data safety
- [ ] Outputs are written to a temp file, validated (reopened, page count checked), then atomically moved.
- [ ] Failure or cancellation leaves the source untouched and cleans temp files.
- [ ] DB rows and files stay consistent (no orphan rows, no orphan files).
- [ ] Edits are stored as parameters (crop quad, rotation, filter); originals retained.
- [ ] Every fallible operation returns `Result<T>` with a typed `AppFailure` — no silent catch.

## 2. Privacy
- [ ] No document text, pixels, filenames or user paths in logs, analytics or exceptions.
- [ ] Permissions requested just in time with an explanation panel.
- [ ] No new network call in a core flow. New dependency audited for network use.

## 3. Boundaries
- [ ] Imports respect the dependency rules in SKILL.md.
- [ ] No feature imports another feature. No feature imports `data` or a concrete adapter.
- [ ] No `dart:io` in pure packages.
- [ ] Public API of each package exported through its barrel file only.

## 4. Offline and capability honesty
- [ ] New engine reports `EngineCapability` (offline?, requiresDownload?, platforms).
- [ ] New conversion registered with a `FidelityClass` and limitations text.
- [ ] UI copy doesn't overstate accuracy, fidelity, or legal standing.

## 5. Performance
- [ ] Heavy work off the UI isolate. No full-resolution decode where a thumbnail suffices.
- [ ] Pages processed incrementally; memory bounded for 100-page documents.
- [ ] Measured on a low-end device or in `apps/lab` before claims are made.

## 6. UX and accessibility
- [ ] Semantic labels on icon buttons; 48dp touch targets; works at 200% text scale.
- [ ] Status not conveyed by color alone. Light and dark verified.
- [ ] Loading, empty, error and success states exist. Success shown only after validation.

## 7. Tests
- [ ] Unit tests for domain logic and geometry/filters.
- [ ] Widget tests for new screens' key states.
- [ ] Fixture/golden tests for engines where output is deterministic.
