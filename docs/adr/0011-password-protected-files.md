# ADR-0011: Protect files with AES-256 PDF (R6) and AES-256 ZIP (WinZip AE-2)

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-28 |
| **Deciders** | Principal Architect, owners of `engine_pdf` and `feature_tools` |

## Context
Users send IDs and tax forms over WhatsApp and email. They need a password on the
file that the recipient can open with standard tools, with no IDSnap account or app.
Everything must run offline, and the password must never be stored or logged.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| PDF: `package:pdf` encryption | Already a dependency | Only for PDFs it creates. It can't re-encrypt existing files, and its RC4/AES-128 support is limited |
| PDF: PDFium via pdfrx | Robust parser | PDFium can decrypt but has no API for writing encryption |
| **PDF: our own R6 writer on the existing `pdf_syntax` reader** | Standard AES-256 (ISO 32000-2 R6), pure Dart, full fidelity (a rewrite, not rasterised). Validated with PDFium and qpdf | We maintain the security-handler code (about 600 lines, covered by tests) |
| PDF: AES-128 (R4) | Accepted by older readers | Weaker. Not needed: R6 opens in Acrobat X+, Chrome/PDFium, pdf.js and Apple PDFKit |
| ZIP: `archive` `ZipEncoder(password:)` | Already in the workspace | Writes AE-1 with "version needed" 2.0, holds the whole file in memory, and has no streaming |
| **ZIP: our own streaming AE-2 writer** | Streams any size in 1 MiB chunks. Writes a correct header (5.1, method 99, 0x9901 v2) | We maintain about 300 lines |
| ZIP: ZipCrypto | Opens everywhere | Broken cryptography. **Never used** |

## Decision
- PDFs become AES-256 PDFs (security handler V5/R6, `/AESV3` crypt filter). The header is PDF 1.7 with
  `/Extensions /ADBE /ExtensionLevel 8`, or 2.0 when the input is already 2.0. The writer rewrites
  every object, encrypts every string and stream, and drops object and xref streams.
  An open password is required. An optional owner password sets `/P`, which can remove print, copy and edit rights.
  If there's no owner password, a random 32-character one is used and all permissions are granted.
- Any other file, or several files, go into one WinZip AE-2 ZIP: AES-256-CTR, HMAC-SHA1 (10 bytes),
  PBKDF2-HMAC-SHA1 with 1000 iterations, and CRC 0. ZIP passwords must be printable ASCII
  because unzip tools encode non-ASCII passwords differently.
- Crypto primitives come from `pointycastle` 4.x (MIT-style Bouncy Castle licence).
- Removing a password uses our own R6 decryptor when the file is R6. Otherwise it uses PDFium's
  `FPDF_SaveAsCopy(FPDF_REMOVE_SECURITY)`, and if that fails, it imports the pages into a new document.
  Every candidate output is reopened with PDFium before it's accepted.

## Consequences
- Positive: recipients need only a standard PDF viewer or 7-Zip/WinRAR/Keka. No network, and no stored password.
- Negative / accepted risks: macOS Archive Utility and older Windows Explorer can't open AES ZIPs.
  The app tells users which tools recipients can use. PDF permissions are advisory, as they are in every viewer.
  ZIP64 is not written, so each archive is limited to 4 GiB.
- Follow-ups: on-device checks of the outputs in Adobe Reader, Chrome, Android and iOS viewers, and Android file managers.

## Validation
- `packages/engines/pdf/test/protect_test.dart`:
  - Known-answer tests: FIPS-197 AES-256, RFC 2202 HMAC-SHA1, RFC 6070 PBKDF2.
  - R6 round trip in pure Dart. qpdf-written R6 fixtures authenticate with our Algorithm 2.B.
  - PDFium opens the output only with the password and reports revision 6 and the permission bits.
  - Passwords are removed from R3/RC4, R4/AES-128 and R6 files written by other tools.
  - `archive` and 7-Zip (`7z t`) verify the ZIP.
- `protected_zip_large_test.dart`: a 96 MiB input adds less than 64 MiB to peak RSS.
- qpdf 12.4 (via pikepdf) opens the R6 outputs, reports R6/V5/AESV3, and `check_pdf_syntax()` finds no problems.
