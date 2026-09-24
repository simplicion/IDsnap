## What & why
<!-- Link the PRD requirement (FR-xx) or issue. One paragraph. -->

## How
<!-- Packages touched, new ports/adapters, ADR link if a technology choice changed. -->

## Screenshots (UI changes)
| Light | Dark | 200% text |
|---|---|---|
| | | |

## Checklist
- [ ] Respects dependency rules (features don't import features, `data`, or concrete engines)
- [ ] No network calls or new network-capable dependencies in core flows
- [ ] No document content, filenames or paths logged (`RedactedLogger` only)
- [ ] Outputs go through `CommitOutput` (validated before "Saved")
- [ ] Empty / loading / error / success states; 48 dp targets; semantic labels
- [ ] Copy follows DESIGN.md §7 (no "perfect", "certified")
- [ ] Tests added/updated; `dart analyze --fatal-infos .` clean
- [ ] Docs updated (`docs/`), `dart run tool/sync_docs.dart` passes
