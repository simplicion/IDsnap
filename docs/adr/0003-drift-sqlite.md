# ADR-0003: Use Drift (SQLite) for library metadata; files on disk for content

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
The library needs search, sort, filters, folders and favorites, with live updates, and it
has to scale to thousands of documents. Binary content must not live in the database.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **Drift** | Typed queries, `watch()` streams, migrations, in-memory tests | build_runner codegen |
| sqflite | Popular | Untyped, no streams |
| Isar / Hive | Fast | Maintenance uncertainty; weaker relational queries |

## Decision
Drift over `sqlite3` (bundled via `drift_flutter`) with the tables `documents` and `folders`.
Files are stored under app-private `documents/` with UUID names. Paths in the DB are relative.
Drafts and settings are small JSON files (`DraftStore`, `SettingsStore`). They don't need
queries, and a draft must survive even a DB migration failure.

## Consequences
- `melos run codegen` is required after schema changes. CI runs it.
- Schema changes need a `MigrationStrategy` step and a migration test.
- `CommitOutput` keeps files and rows consistent: it deletes the file if the insert fails.
