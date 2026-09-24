# Contributing to DocScan

Thanks for helping. This project holds a high bar for correctness, privacy and honesty, so
please read this first.

## Workflow

1. Branch from `main`: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`.
2. Keep PRs small and focused (under ~400 changed lines where possible).
3. Before pushing:
   ```bash
   dart run melos run format
   dart analyze --fatal-infos .
   dart run melos run test
   dart run tool/sync_docs.dart      # if you touched docs/
   ```
4. Fill in the PR template checklist. CI must be green.

## Commit messages

Conventional Commits: `feat(tools): add compress-to-size`, `fix(scan): keep draft on rotate`,
`docs(adr): 0009 password-protected PDFs`.

## Architecture rules (enforced in review)

- Features never import other features, `docscan_data`, or concrete engines.
- New capabilities start as a **port** in `packages/domain`, then get an **adapter** in an engine.
- No network dependencies in core packages ([ADR-0008](docs/adr/0008-privacy-no-network.md)).
- Every output goes through `CommitOutput`.
- Technology choices need an ADR ([template](docs/adr/0000-template.md)).

## UI rules

Follow [DESIGN.md](docs/design/DESIGN.md): tokens only (no raw hex), all four states, 48 dp
targets, semantic labels, light and dark, 200% text, copy per §7.

## Reporting security or privacy issues

Please don't open a public issue. Contact the maintainers privately (address TBD).
