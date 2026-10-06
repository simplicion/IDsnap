# DocScan Documentation

**Scan, organize and convert documents on your phone. No account. No upload. Core tools work offline.**

DocScan is an offline-first document scanner, PDF toolkit, OCR and converter for Android and
iOS, built with Flutter. These docs are the source of truth for product, design and
engineering decisions.

## Start here

| If you want to… | Read |
|---|---|
| Understand what we're building and why | [Product Requirements](product/PRD.md) |
| Design or build UI | [Design System & UX](design/DESIGN.md) |
| Understand the code structure | [Architecture Overview](architecture/overview.md) |
| Know why each library was chosen | [Tech Stack](architecture/tech-stack.md) |
| Set up your machine | [Getting Started](guides/getting-started.md) |
| Add a new tool | [Contributing a Tool](guides/contributing-a-tool.md) |
| Test or release | [Testing](guides/testing.md) · [Release](guides/release.md) |
| See past decisions | [ADR index](adr/0000-template.md) |

## What's in the app

- **Scan**: platform document camera with edge detection, manual 4-corner crop, five filters, multi-page.
- **PDF tools**: images → PDF, merge, split, organize, compress, PDF → images, searchable PDFs.
- **Image tools**: passport/visa/ID photo crop presets, compress to a target size, resize.
- **Text**: on-device OCR with copy and TXT/DOCX export.
- **Convert**: DOCX, XLSX, PPTX, CSV, HTML, Markdown and TXT conversions, each with an honest fidelity label.
- **Files**: search, folders, favorites, rename, share, save to device.

## Promises we keep in code

1. Your documents, IDs and codes never leave the phone; the app's own code makes no network calls
   ([ADR-0008](adr/0008-privacy-no-network.md)). IDSnap is free and shows Google ads on a few
   screens, never in the vault ([ADR-0013](adr/0013-free-with-ads.md)).
2. Originals are never modified. Every output is validated before "Saved" appears.
3. Every conversion states its fidelity. Scans are copies, not certified originals.
