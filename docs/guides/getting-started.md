# Getting Started

## Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter | stable (3.35+; tested with 3.47) | `flutter --version` |
| Dart | 3.9+ (ships with Flutter) | `dart --version` |
| Android SDK | API 36 build tools, a device or emulator with Google Play | `flutter doctor` |
| Xcode (macOS only) | 16+, CocoaPods | `pod --version` |
| Docker (optional) | 24+ | `docker --version` |

## First run

```bash
git clone <repo> docscan && cd docscan
flutter pub get                       # resolves the whole workspace (one lockfile)
dart run melos run codegen            # generates Drift code in packages/data
dart run melos run analyze            # static analysis, must be clean
dart run melos run test               # all package tests
```

Run the apps:

```bash
dart run melos run run:scanner        # product app on a connected Android/iOS device
dart run melos run run:docs           # documentation site in Chrome
dart run melos run run:lab            # engine lab in Chrome
```

Or directly: `cd apps/scanner && flutter run`.

## Everyday commands

| Task | Command |
|---|---|
| Format | `dart run melos run format` |
| Format check (CI) | `dart run melos run format:check` |
| Analyze | `dart analyze --fatal-infos .` |
| Test one package | `cd packages/engines/imaging && flutter test` |
| Sync docs into the docs app | `dart run tool/sync_docs.dart` |
| Build Android APK | `cd apps/scanner && flutter build apk --release` |
| Build docs site | `dart run tool/sync_docs.dart && cd apps/docs && flutter build web` |
| Docs in Docker | `docker compose up --build docs` → http://localhost:8080 |

## Where things live

Start with [Architecture overview](../architecture/overview.md). In short:
- UI for a feature → `packages/features/<feature>/`
- A new capability → a port in `packages/domain/lib/src/ports/`, plus an adapter in `packages/engines/<engine>/`
- Wiring → `apps/scanner/lib/bootstrap.dart`
- Visual tokens and components → `packages/design_system/`

## Working with the principal-architect skill

The repo ships a Claude Code skill at `.claude/skills/principal-architect/`. Ask for design
reviews, ADRs or feature plans, and it applies the dependency rules and review checklist
used in this codebase.
