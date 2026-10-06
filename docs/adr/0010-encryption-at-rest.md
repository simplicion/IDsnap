# ADR-0010: Encrypt the vault at rest (AES-256-GCM files, SQLCipher database)

| | |
|---|---|
| **Status** | Accepted (implementation shipped; the "encrypted" marketing claim waits for an independent security review) |
| **Date** | 2026-09-28 |
| **Deciders** | Principal Architect, owners of `data`, `engines/security`, `features/*` |

## Context
Roadmap B3 ([roadmap](../product/roadmap-vault-id-card.md#b3-encryption-at-rest-separate-adr-required-before-building)).
IDSnap stores passports, ID cards, bank details and 2FA metadata. Until now, files under
`<app documents>/docscan` and `library.sqlite` were plaintext. Android and iOS sandboxing protect
them from other apps, but not from a rooted or jailbroken phone, forensic extraction, a leaked
OS backup, or a debug build of another app with the same signature. The requirements are:

- Offline only (ADR-0008). No server-side key escrow, no account.
- Large PDFs (50 MB+) must stay usable: streaming, bounded memory, off the UI isolate.
- Engines that need a real file path (PDFium, ML Kit, platform viewers, the share sheet) must
  keep working.
- Existing installs have plaintext data. It must be migrated without losing anything, even if
  the app is killed halfway.
- Tests run on a Windows host without a phone.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **A. Per-file AES-256-GCM (chunked) + SQLCipher, master key in Keystore/Keychain via `flutter_secure_storage`** | Standard primitives; streaming; authenticated (tamper-evident) per chunk; DB fully encrypted incl. indexes; testable on the host (`cryptography` pure-Dart fallback, SQLCipher DLL) | Temp plaintext needed for path-based engines; device-bound key → OS backup can't restore to a new phone |
| B. Android `EncryptedFile` / iOS Data Protection only | Zero crypto code | Android `EncryptedFile` (Jetpack security-crypto) is deprecated; iOS Data Protection `complete` breaks background work and is not under our control; two different formats; no DB story |
| C. One key per vault, AES-CTR + HMAC | Faster in pure Dart | Home-grown AEAD composition; no per-file key isolation |
| D. Field-level encryption in SQLite instead of SQLCipher | No native lib | Leaks schema, row counts, index contents and file names; every query must decrypt |

## Decision
**Option A.**

### Key hierarchy
| Key | What | Where |
|---|---|---|
| Master key (MK) | 32 random bytes (`Random.secure`), key id `1` | `flutter_secure_storage` item `vault.master_key.v1` (Android: value encrypted with an Android Keystore key, `resetOnError: false`; iOS: Keychain, `first_unlock_this_device`, not synchronizable) |
| File key (FK) | 32 random bytes per file (re-encrypting a file makes a new FK) | In the file header, wrapped with MK (AES-256-GCM) |
| DB key | HKDF-SHA256(MK, salt `idsnap.vault`, info `sqlcipher/v1`) | Never stored; passed as a raw key (`PRAGMA key = "x'…'"`, no PBKDF2) |
| Key check value (KCV) | First 8 bytes of HMAC-SHA256(MK, `idsnap/kcv/v1`), hex | `vault.json` in the vault root (not secret) |

Keys are never logged (`RedactedLogger` drops long strings anyway), never written to SQLite or
settings, and never leave the device.

**Fail closed.** A new MK is created only when the vault holds no encrypted data (no KCV in
`vault.json`, no file with the vault magic, and no encrypted `library.sqlite`). If encrypted
data exists and the key is missing or its KCV doesn't match (an OS backup restored to another
phone, a wiped Keystore), IDSnap shows a recovery screen instead of silently creating a new key.
The screen explains that the files can't be read on this phone and offers "Erase vault and
start fresh" (confirmed twice); the recovery path is importing an "Export all data" ZIP.

### File format (`IDSV`, version 1)
All integers big-endian. One header, then chunks.

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | Magic `89 49 44 53 56 4C 54 1A` (`\x89IDSVLT\x1A`; the high byte and `^Z` keep it from being valid text or any document format we import) |
| 8 | 1 | Format version = `1` |
| 9 | 1 | Algorithm = `1` (AES-256-GCM, 96-bit nonce, 128-bit tag) |
| 10 | 1 | log2(chunk size) = `18` (256 KiB of plaintext per chunk; 12–24 accepted) |
| 11 | 1 | Reserved = `0` |
| 12 | 4 | Master key id |
| 16 | 12 | Wrap nonce (random) |
| 28 | 48 | Wrapped FK: AES-256-GCM(MK, wrap nonce, FK, AAD = header bytes 0–15) = 32-byte ciphertext ‖ 16-byte tag |
| 76 | 8 | Chunk nonce prefix (random) |
| 84 | … | Chunks |

Chunk *i* (0-based) = AES-256-GCM(FK, nonce = prefix ‖ u32(*i*), plaintext chunk,
AAD = header bytes 0–83 ‖ u32(*i*) ‖ u8(final)) = ciphertext ‖ 16-byte tag. Every chunk but
the last holds exactly one full chunk of plaintext; the last one holds 0…chunk size bytes and
is sealed with final = 1. An empty file is one empty final chunk (84 + 16 bytes).

What this prevents:
- **Tampering:** any flipped bit in a chunk fails that chunk's tag; any header change fails the
  key unwrap (bytes 0–15) or every chunk (bytes 0–83 are in every chunk's AAD).
- **Reordering / duplication:** the chunk index is in the nonce and the AAD.
- **Truncation:** cutting at a chunk boundary makes a non-final chunk the last one, and its tag
  (sealed with final = 0) fails. Cutting mid-chunk or appending fails the length check or a tag.
- **Cross-file swaps:** each file has its own FK.
- **Nonce reuse:** FKs are single-use random keys; within a file, nonces are distinct by index.

Decryption writes plaintext only after each chunk authenticates, into a `.part` file that is
renamed only when the final chunk verifies; a failure deletes the partial output.

### Performance
Pure-Dart AES-GCM from `cryptography` measures ~5.5 MB/s on a desktop (AOT), far too slow for
a 50 MB PDF on a phone. The cipher therefore uses `cryptography_flutter` (`FlutterAesGcm`:
`javax.crypto` / Conscrypt on Android, CryptoKit on iOS). Streaming jobs run in a background
isolate that attaches to the platform channels with `BackgroundIsolateBinaryMessenger` and
registers the plugin there. Only plain data (paths, key bytes, the root isolate token) crosses
the isolate boundary. Chunks are 256 KiB, so memory stays at a few chunks whatever the file
size. On hosts without the plugin (tests, desktop) the same format is produced by
`DartAesGcm`. Target: 50 MB encrypt or decrypt in a few seconds on a mid-range phone. This
must be measured on devices (`integration_test/vault_crypto_perf_test.dart`).

### Database
`sqlite3` 3.x is switched to its SQLCipher build with the hook user-define
`hooks.user_defines.sqlite3.source: sqlcipher` in the workspace `pubspec.yaml`, on every
platform, including the Windows test host, so the key path is tested for real. The executor
runs `PRAGMA key` first, then refuses to continue if `PRAGMA cipher_version` is empty (a plain
SQLite build would silently ignore the key).

**Plaintext → SQLCipher migration** (before Drift opens the file), crash-safe:
1. `library.sqlite` starts with `SQLite format 3\0` → it is plaintext.
2. Delete any stale `library.sqlite.enc-tmp`. Open the plaintext DB, `ATTACH` the tmp file with
   the DB key, `SELECT sqlcipher_export('encrypted')`, copy `user_version`, `DETACH`.
3. Verify: open the tmp file with the key, `PRAGMA cipher_integrity_check` and
   `integrity_check`, and compare the row count of every table with the source.
4. Rename `library.sqlite` → `library.sqlite.plain-old`, then `enc-tmp` → `library.sqlite`.
5. Shred `library.sqlite.plain-old` and its `-wal`/`-shm`/`-journal` files.

On startup, a leftover state is completed: `plain-old` + `enc-tmp` and no `library.sqlite` →
step 4 again; encrypted `library.sqlite` + `plain-old` → step 5; plaintext `library.sqlite` →
start over (the tmp file is discarded).

### Migrating existing files
Files under `documents/`, `thumbs/`, `originals/` and `signatures/` without the magic are
encrypted in place, one at a time. The state of each file is visible on disk, so no journal
is needed and the migration resumes wherever it stopped:
1. Encrypt `x` → `x.enc-part`, fsync, verify by decrypting it and comparing SHA-256 digests.
2. Rename `x` → `x.plain-old`, then `x.enc-part` → `x`. The DB keeps the same relative path.
3. Shred `x.plain-old`.

Recovery: `x` plaintext + `x.enc-part` → delete the part and redo; no `x` + `x.plain-old` +
`x.enc-part` → finish step 2; no `x` + only `x.plain-old` → rename it back and redo; encrypted
`x` + `x.plain-old` → shred it. A killed app loses at most the work on one file, never data.
Startup shows a progress screen when there's work to do.

### Access paths
- `FileStore.read` / `readText` / `size` decrypt transparently (by magic), so every
  byte-oriented reader keeps working unchanged.
- `commit`, `writeThumbnail` and `importOriginal` encrypt on the way in (tool outputs, scans,
  imports, thumbnails).
- Path-based consumers (PDF viewer, PDFium tools, ML Kit, `Image.file`) get a plaintext copy
  from `PlainFileAccess.decryptToTemp` in the app **cache** directory (never shared storage,
  never backed up), released with `releaseTemp` (shred) after use. Every leftover is shredded
  at the next launch. Library inputs to tools are decrypted when picked.
- Sharing: `exportCopy` decrypts into the cache share folder; the copy is shredded after the
  share sheet returns (with a short grace period, since the target app may still be reading)
  and at the next launch.
- "Export all data" writes a **decrypted** ZIP (documents, folders, secure notes), behind
  re-authentication (always, not only when App Lock is on) and a warning. A password-protected
  export is not built in yet: the warning points to Tools › Protect file (AES-256 ZIP,
  ADR-0011). Import encrypts on the way in.
- Library inputs to tools (including Protect file and "Protect & share") are decrypted when
  picked (`openDocumentInput`); nobody releases those copies explicitly, so later decrypts shred
  copies older than 30 minutes, and every launch shreds all of them.
- Stores outside the `FileStore` use the same cipher (`fileCipherProvider`): saved signatures
  (`signatures/*.png` + `index.json`) and the QR scan history (`qr/history.json`, migrated on
  first read). Secure notes live in the SQLCipher database.
- Shredding = overwrite with zeros, fsync, delete. On flash storage with wear levelling this is
  best effort; the real guarantee is that plaintext only ever sits in the cache for the
  duration of a view/share.

### Backups
`android:allowBackup="false"` plus `dataExtractionRules` that exclude everything from cloud
backup and device transfer: the MK can't leave the Keystore, so a restored vault would be
unreadable, and restoring the old secure-storage prefs would only produce undecryptable
garbage. iOS Keychain items are `ThisDeviceOnly`, so they don't move to a new phone either.
**An OS backup can't restore encrypted data to a new device. "Export all data" is the
migration path**, and Settings says so.

## Consequences
- Positive: files, thumbnails, in-progress scans, saved signatures, notes and the whole DB are
  encrypted on the phone; tampering is detected; old installs are migrated safely.
- Negative / accepted risks:
  - Plaintext exists briefly in the app cache while viewing, processing or sharing.
  - The MK is only as strong as the Keystore/Keychain; a compromised, unlocked, rooted phone
    can read it. This protects data at rest, not a running compromised device.
  - Device change needs an export; losing the phone without an export loses the vault.
  - SQLCipher (BSD-style licence) and OpenSSL (Apache-2.0) must be listed in the licences
    screen (Flutter collects them from the packages).
- Not encrypted (no document content): `settings.json`, the scan draft index
  `drafts/current.json` (page geometry and paths; the page images themselves are encrypted),
  `vault.json` (key check value), and billing/trial state. PIN hashes, 2FA secrets and the
  master key are in the platform keystore.
- Follow-ups:
  - Independent security review before marketing may say "encrypted" (roadmap B3).
  - Measure the 50 MB target on a low/mid Android and an iPhone.
  - Key rotation (the header carries a key id; rotation would re-wrap FKs only).

## Validation
- Unit tests: format round trip (empty, 1 byte, exact chunk multiples, multi-MB), tamper per
  chunk, header tamper, truncation at and inside chunk boundaries, reordering, wrong key;
  key manager with fake secure storage (create once, fail closed, KCV mismatch).
- Data tests: SQLCipher open with the key, wrong key rejected, plaintext → SQLCipher migration
  (row counts) and resume after each crash point; file migration resumed after simulated
  interruptions; temp cleanup; export/import; notes v4 → v5.
- Device: `integration_test/vault_crypto_perf_test.dart` for throughput.
