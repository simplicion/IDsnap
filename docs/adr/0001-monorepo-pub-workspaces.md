# ADR-0001: Use a Dart pub-workspace monorepo with melos scripts

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
We ship three apps (scanner, docs, lab) that share domain logic, engines and a design
system. We want enforced module boundaries, a single dependency resolution, and fast
onboarding on Windows, macOS and Linux.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| Single app package, folders per feature | Simple | Boundaries by convention only; slow analysis |
| Multi-repo | Hard isolation | Version drift, painful cross-cutting changes |
| **Pub workspaces + melos** | One lockfile, real package boundaries, `resolution: workspace` | Newer tooling (Dart ≥ 3.6) |

## Decision
Use one git repository with a root `pubspec.yaml` that declares `workspace:` members
(`apps/*`, `packages/**`). Every member uses `resolution: workspace`. Use melos 7 (config
under `melos:` in the root pubspec) for cross-package scripts.

## Consequences
- The package graph enforces boundaries: a feature can't import `data` unless its pubspec
  says so, and review blocks that.
- One `flutter pub get` at the root. Dependency upgrades are atomic.
- Contributors need Dart 3.9+ / Flutter stable.

## Validation
CI runs `dart analyze --fatal-infos` at the root and `flutter test` per package on every PR.
