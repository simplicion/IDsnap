# Contributing a Tool

This walkthrough adds a hypothetical **"Add page numbers"** PDF tool. Follow the same steps
for any tool.

## 1. Frame it
- Which user job does it serve? Add or extend an FR in [PRD](../product/PRD.md).
- What's its fidelity? If it re-renders pages, it's lossy and needs a `FidelityNote`.
- Does it work offline? It must, or it doesn't ship.

## 2. Port first (domain)
If an existing port can't do it, add a method to the port in
`packages/domain/lib/src/ports/`, for example:

```dart
/// Stamps "n / N" at the bottom of every page. New file; input untouched.
Future<Result<Uint8List>> addPageNumbers(String path, PageNumberStyle style);
```

Add any option types to `packages/domain/lib/src/entities/options.dart`. Keep domain pure
Dart: no Flutter, no `dart:io`.

## 3. Implement the adapter (engine)
Implement it in the engine (e.g. `packages/engines/pdf`). Put heavy work in `runHeavy` or
native code. Return typed failures (`FailureCode.corruptFile`, `passwordProtected`, …) and
never throw. Add tests with a generated PDF fixture: build it, run the tool, reopen it,
check the page count.

## 4. Add the screen (feature)
In `packages/features/tools/lib/src/<tool>/`:
- `<tool>_controller.dart`: a `Notifier` holding `idle → ready → processing → success/failure`.
- `<tool>_screen.dart`: use the shared tool layout (pick → options → preview → sticky primary action).
- Save outputs via `commitOutputProvider`. Never write to the library directly.
- Register the route (`ToolId` in `docscan_contracts` + the tool routes list) and add a
  `ToolTile` in the Tools hub.

## 5. Design and copy
Follow [DESIGN.md](../design/DESIGN.md): verbs on buttons, all four states, 48 dp targets,
semantic labels, light and dark, 200% text.

## 6. Prove it
- `dart analyze --fatal-infos .` is clean.
- Package tests pass. There's a widget test for the screen's success and error states.
- Run it in airplane mode on a device.
- Update the docs (PRD matrix, DESIGN tool table), then run `dart run tool/sync_docs.dart`.

## Review checklist
See `.claude/skills/principal-architect/references/review-checklist.md`.
