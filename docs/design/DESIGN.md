# DocScan Design System & UX Specification

| | |
|---|---|
| **Status** | v1.1, source of truth for UI |
| **Implementation** | `packages/design_system` (`tokens.dart`, `theme.dart`, `widgets.dart`, `feedback.dart`) |
| **Platforms** | Android & iOS phones first, then tablets; web later |

> **Design in one sentence:** a calm, friendly utility that gets a paper document into a clean,
> shareable file in under a minute, and never makes you wonder where your file went or who can see it.

---

## 1. Design principles

| # | Principle | In practice |
|---|---|---|
| 1 | **One obvious next step** | Every screen has one primary action (filled button or hero card). Everything else is secondary. |
| 2 | **Show, don't make them guess** | Live previews for crop, filters, compression size and preset sizes. Before/after for anything lossy. |
| 3 | **Forgiving by default** | Non-destructive edits, undo for deletes, drafts that survive crashes, "Save a copy" instead of overwrite. |
| 4 | **Honest and calm** | Plain words, real progress only, fidelity notes on conversions, no "certified" or "perfect" claims. |
| 5 | **Private is visible** | "Works offline" badges and a privacy line on Home. Share is always an explicit user action. |
| 6 | **Thumb-friendly** | Primary actions in the bottom 40% of the screen; 48 dp minimum targets; 52 dp buttons. |
| 7 | **Native feel, one brand** | Material 3 on Android, Cupertino transitions and back-swipe on iOS, the same tokens everywhere. |

## 2. Personas and daily-life jobs

| Persona | Job-to-be-done | Design implication |
|---|---|---|
| **Asha, student** | "The admission portal wants a 35×45 mm photo under 50 KB and my marksheet as a PDF." | Passport presets with mm sizes shown, "compress to size" field in KB, readable success sheet with the final size. |
| **Mr. Rao, teacher** | "Scan 12 worksheets fast and send them to the class group." | Continuous capture, bulk filter "Apply to all", Share straight from the success sheet. |
| **Priya, office worker** | "Merge the signed form with its annexure, in the right order." | Multi-select in Files, then Merge with drag-to-reorder. |
| **Imran, shop owner** | "Find last month's invoice from Kumar Traders." | Search by name, folders, favorites, searchable PDFs. |
| **Everyone** | "Copy the text from this notice." | Extract text: pick → review → Copy, in 3 taps. |

## 3. Information architecture

```
┌──────────────────────────── App shell ────────────────────────────┐
│  Home            Files             Tools              Settings    │
│  ├ Scan (hero)   ├ Search/sort     ├ PDF tools        ├ Appearance│
│  ├ Import        ├ Filter chips    │  Merge · Split   ├ Scanning  │
│  ├ Quick tools   ├ Folders         │  Organize        ├ OCR lang  │
│  └ Recent files  ├ Document viewer │  Compress        ├ Storage   │
│                  └ Multi-select    │  PDF → images    ├ Privacy   │
│                                    ├ Image tools      └ About     │
│                                    │  Photo crop · Compress       │
│                                    │  Resize · Images → PDF       │
│                                    ├ Text: Extract text (OCR)     │
│                                    └ Convert (registry)           │
└───────────────────────────────────────────────────────────────────┘
Full-screen flows (cover the tab bar): Scan → Review → Crop → Save
```

**Navigation rules**
- Phones (< 600 dp): bottom `NavigationBar`, 4 destinations, labels always shown.
- Tablets and web (≥ 840 dp): `NavigationRail` on the left, with a two-pane Files view (list + preview).
  From 600 to 839 dp: rail without labels.
- Detail and tool screens are pushed on the root navigator and cover the tab bar.
- Android predictive back and iOS back-swipe on every pushed screen. Unsaved work asks before leaving.
- Route contract: `Routes` in `packages/contracts/lib/src/routes.dart`.

## 4. Visual foundations

### 4.1 Color tokens

Widgets read colors from `Theme.of(context).colorScheme` or `context.ds` (a `DsColors`
extension). They never use hex values directly.

**Material `ColorScheme`**

| Role | Light | Dark | Used for |
|---|---|---|---|
| `primary` | `#2457D6` | `#8EABFF` | Primary buttons, hero card, active states |
| `onPrimary` | `#FFFFFF` | `#14234A` | Text and icons on primary |
| `primaryContainer` | `#EAF0FF` | `#223A78` | Nav indicator, selected chips |
| `onPrimaryContainer` | `#14234A` | `#DCE5FF` | Content on primaryContainer |
| `secondary` | `#0E8A7E` | `#6FD6C8` | Secondary accents |
| `secondaryContainer` | `#DDF5F1` | `#0F4B44` | Pills and badges |
| `onSecondaryContainer` | `#053B35` | `#C4F2EA` | Pill text |
| `tertiary` | `#9A5B00` | `#FFC36B` | Rare highlight |
| `error` | `#B42318` | `#FF8D86` | Destructive actions, errors |
| `errorContainer` | `#FDE7E5` | `#5A1D18` | Error surfaces |
| `surface` | `#FFFFFF` | `#191C22` | Cards, sheets, dialogs, nav bar |
| `onSurface` | `#171A21` | `#F3F5F8` | Primary text |
| `onSurfaceVariant` | `#5F6877` | `#B4BBC7` | Secondary text and icons |
| `surfaceContainerLow` | `#FAFBFC` | `#15181D` | Subtle fills |
| `surfaceContainer` | `#F7F8FA` | `#191C22` | Grouped backgrounds |
| `surfaceContainerHigh` | `#EEF1F6` | `#252A33` | Text fields, segmented backgrounds |
| `surfaceContainerHighest` | `#E6EAF1` | `#2E3440` | Progress track |
| `outline` | `#B9C1CE` | `#5A6373` | Outlined buttons |
| `outlineVariant` | `#DDE2EA` | `#343B47` | Hairlines |
| `inverseSurface` | `#171A21` | `#F3F5F8` | Snackbars |

**`DsColors` extension (semantic extras)**

| Token | Light | Dark | Used for |
|---|---|---|---|
| `canvas` | `#F7F8FA` | `#101216` | Scaffold background (cards float on it) |
| `border` | `#DDE2EA` | `#343B47` | Card borders, dividers |
| `textSecondary` | `#5F6877` | `#B4BBC7` | Captions, metadata |
| `success` / `successContainer` | `#197A4A` / `#E3F5EB` | `#69D5A0` / `#123A27` | Offline badge, success sheet |
| `warning` / `warningContainer` | `#9A5B00` / `#FFF1DC` | `#FFC36B` / `#3A2A10` | Fidelity notes, lossy warnings |
| `pdf` | `#D14343` | `#FF8A80` | PDF file icon |
| `image` | `#7A4FD6` | `#C3A8FF` | Image file icon |
| `text` | `#3B6FD9` | `#9BB8FF` | Text/DOCX file icon |
| `office` | `#1C8C5E` | `#7ADBB0` | Sheet/CSV file icon |

**Color rules**
- File-type colors always come with an icon and a label; color alone never carries meaning.
- Dark mode is a first-class theme with its own tuned values, not an inversion. Surfaces get
  lighter as they rise (canvas `#101216` → surface `#191C22` → high `#252A33`).
- Scan previews sit on a neutral surface so paper edges stay visible in both themes. Page
  images are never tinted.
- Every text/background pair must meet 4.5:1 (body) or 3:1 (≥ 18 sp or bold 14 sp). Checked
  pairs: `onSurface/surface` ≈ 17.4:1 light and ≈ 15.6:1 dark; `primary/white` ≈ 6.2:1;
  `textSecondary/canvas` ≈ 5.3:1 light.

### 4.2 Typography

The platform system font (Roboto on Android, SF Pro on iOS). **No runtime font downloads**:
`google_fonts` is deliberately excluded because it fetches fonts over the network.

| Style | Size / line height | Weight | Used for |
|---|---|---|---|
| `displaySmall` | 28 / 34 | 600 | Home greeting |
| `headlineSmall` | 24 / 30 | 600 | Screen titles on large layouts |
| `titleLarge` | 20 / 26 | 600 | App bar titles, empty-state titles |
| `titleMedium` | 17 / 24 | 600 | Section headers, dialog titles |
| `titleSmall` | 15 / 20 | 600 | Card titles, tool names |
| `bodyLarge` | 16 / 24 | 400 | Paragraphs, OCR text |
| `bodyMedium` | 14 / 20 | 400 | Default body |
| `bodySmall` | 12.5 / 18 | 400 | Metadata, captions |
| `labelLarge` | 15 / 20 | 600 | Buttons |
| `labelMedium` | 12 / 16 | 500 | Pills, nav labels |

Text must scale to 200% without clipping. Never fix a height on a box that contains text;
use `maxLines` plus ellipsis only for metadata.

### 4.3 Spacing, radii, elevation, motion

| Token | Value | | Token | Value |
|---|---|---|---|---|
| `Space.x1` | 4 | | `Radii.sm` | 8 (chips, small controls) |
| `Space.x2` | 8 | | `Radii.button` | 12 (buttons, fields, snackbars) |
| `Space.x3` | 12 | | `Radii.card` | 16 (cards, tiles) |
| `Space.x4` | 16 (= `Space.gutter`) | | `Radii.sheet` | 24 (sheets, dialogs, hero) |
| `Space.x5` | 20 | | | |
| `Space.x6` | 24 | | `Motion.fast` | 150 ms (micro-interactions) |
| `Space.x8` | 32 | | `Motion.medium` | 240 ms (transitions) |
| `Space.x10` | 40 | | `Motion.curve` | `easeOutCubic` |
| `Space.x12` | 48 | | | |

- **Elevation:** none on cards. A 1 px `border` token separates surfaces. Shadows appear only
  on floating elements (FAB, dragged page thumbnail, magnifier).
- **Motion:** respect `MediaQuery.disableAnimations`. Never animate a fake progress bar; the
  spinner is indeterminate unless real progress is known.

### 4.4 Iconography

Material Symbols **Rounded** (`Icons.*_rounded`), 24 dp. Key icons:

| Concept | Icon |
|---|---|
| Scan | `document_scanner_rounded` |
| Import photos | `photo_library_rounded` |
| Import file | `upload_file_rounded` |
| PDF | `picture_as_pdf_rounded` |
| Merge | `merge_type_rounded` |
| Split | `call_split_rounded` |
| Organize | `view_module_rounded` |
| Compress | `compress_rounded` |
| Crop | `crop_rounded` |
| Passport photo | `portrait_rounded` |
| Resize | `photo_size_select_large_rounded` |
| OCR | `text_snippet_rounded` |
| Convert | `swap_horiz_rounded` |
| Offline | `cloud_off_rounded` |
| Share | `ios_share_rounded` (iOS) / `share_rounded` (Android) |

## 5. Component catalog (→ `packages/design_system`)

| Component | API | Rules |
|---|---|---|
| **HeroAction** | `HeroAction(icon, title, subtitle, onTap)` | One per screen at most. Primary fill, 24 radius, whole card tappable, announced as a button. |
| **ToolTile** | `ToolTile(icon, title, subtitle, onTap, color?, badge?)` | Grid of 2 columns on phones (3–4 on tablets). Title ≤ 2 lines. Optional `Pill` badge ("New"). |
| **IconBadge** | `IconBadge(icon, color?, size)` | Tinted square (12% alpha) with a 30% radius. Used in tiles, rows and empty states. |
| **Pill** | `Pill(label, icon?, color?, background?)` | Status and metadata tags. Not tappable. |
| **OfflineBadge** | `OfflineBadge(label?)` | Green success pill with a cloud-off icon. Only on features verified offline. |
| **SectionHeader** | `SectionHeader(title, action?, onAction?)` | Marked as a header for screen readers. |
| **FidelityNote** | `FidelityNote(label, explanation, limitations)` | Shown on every conversion and lossy tool before the user runs it. |
| **EmptyState** | `EmptyState(icon, title, message, actionLabel?, onAction?)` | One friendly sentence and one action. |
| **FailureView** | `FailureView(AppFailure, onRetry?)` | Title + recovery from `FailureCode`, never a raw exception. |
| **ProgressPanel** | `ProgressPanel(label, progress?, onCancel?)` | Determinate only with real progress; Cancel when safe. |
| **Snackbars** | `showAppSnack`, `showFailureSnack` | Floating, 12 radius; undo action for deletes (4 s). |
| **Dialogs** | `confirmAction(destructive:)`, `promptText` | Destructive confirm uses the `error` fill. Rename preselects the text. |
| **Formatters** | `formatBytes`, `formatRelativeDate`, `formatVisual(format)` | "1.4 MB", "Yesterday", icon + color per format. |
| **Buttons** | Material Filled / Outlined / Text | Filled = primary (52 dp high), Outlined = secondary, Text = tertiary/cancel. |

## 6. Screens

Notation: `[Primary]` filled button, `(Secondary)` outlined, `‹ ›` icon button.

### 6.1 Home

```
┌─────────────────────────────────────┐
│ Good evening                    ‹⚙›│
│ Your documents stay on this phone.  │
│ [☁̸ Works offline]                   │
│ ┌─────────────────────────────────┐ │
│ │ ▣  Scan a document            → │ │  ← HeroAction
│ │    Auto-crop, clean up, save PDF│ │
│ └─────────────────────────────────┘ │
│ ┌──────────────┐ ┌──────────────┐   │
│ │ 🖼 Import     │ │ ⤒ Import     │   │
│ │   photos     │ │   file       │   │
│ └──────────────┘ └──────────────┘   │
│ Quick tools                See all  │
│ [Passport] [Compress] [Merge] [Text]│  ← horizontal ToolTiles
│ Recent                     See all  │
│ ▤ Marksheet.pdf  · 3 pages · 420 KB │
│ ▤ Rent receipt   · Today            │
├─────────────────────────────────────┤
│  Home    Files    Tools   Settings  │
└─────────────────────────────────────┘
```

| State | Behavior |
|---|---|
| First run / empty | Recent shows `EmptyState`: "Your scans will appear here", with the action "Scan your first document". |
| Draft exists | A banner above the hero: "You have an unsaved scan (3 pages)" with (Discard) and [Continue]. |
| Loading | Recent shows 3 skeleton rows. No spinner blocks the hero. |

### 6.2 Scan flow

**Capture** uses the platform scanner UI (ML Kit / VisionKit). If it's unavailable
(capability check), a sheet explains: "The camera scanner needs a one-time component from
Google Play. You can still import photos and crop them here." It offers [Import photos] and (Try again).

**Review**

```
┌─────────────────────────────────────┐
│ ‹←›  Review · 3 pages      [Save]   │
│ ┌─────────────────────────────────┐ │
│ │                                 │ │
│ │        current page preview     │ │  ← pinch-zoom
│ │      (edits applied, cached)    │ │
│ │                                 │ │
│ └─────────────────────────────────┘ │
│  ‹Crop› ‹Rotate› ‹Filter› ‹Adjust› ‹Retake› ‹Delete›
│ ┌──┐┌──┐┌──┐┌ + ┐                    │  ← page tray, long-press to drag
│ │1 ││2 ││3 ││Add│                    │
│ └──┘└──┘└──┘└───┘                    │
└─────────────────────────────────────┘
```

- **Filter sheet:** horizontal previews of all five filters rendered from a thumbnail, with the
  selected one outlined in `primary`. A switch applies the filter to all pages. A "Compare"
  button, held down, shows the original.
- **Adjust sheet:** brightness and contrast sliders (−100 to +100), with a Reset action.
- **Crop screen:** full-bleed image with 4 corner handles (48 dp hit area, 20 dp visual) and
  edge midpoints. A magnifier loupe (2.5×) appears above the finger while dragging. Actions:
  (Auto detect), (Full page), [Done]. A low-confidence detection shows a warning pill: "Check the corners".
- **Save sheet:** name (default "Scan 24 Sep 2026 14:05"), folder, page size segmented
  control (A4 · Letter · Legal · Fit), quality (Small · Balanced · High, with an estimated
  size), a "Make text searchable" switch (Latin), and [Save PDF].
- **Processing:** `ProgressPanel` "Creating PDF… page 2 of 3" with real progress.
- **Success sheet:** check icon in `success`, "Saved · 3 pages · 612 KB", then [Share],
  (Save to device), (Open), and (Done).
- **Leaving with unsaved pages:** confirm "Keep this scan as a draft?" with (Discard) and [Keep draft].

### 6.3 Files

```
┌─────────────────────────────────────┐
│ Files                       ‹▦› ‹⋮› │
│ ┌ 🔍 Search documents ────────────┐ │
│ [All] [PDFs] [Images] [Text] [★]    │
│ Folders  ▸ Receipts (12) ▸ College  │
│ ─────────────────────────────────── │
│ ▤ Marksheet            ★        ⋮  │
│   PDF · 3 pages · 420 KB · Today    │
│ ▤ Passport photo                ⋮  │
│   JPG · 48 KB · Yesterday           │
│                                ( + )│  ← FAB: Scan
└─────────────────────────────────────┘
```

- Long-press enters multi-select. The contextual bar offers Share, Merge (PDFs only), Move and Delete.
- The row overflow menu: Open, Rename, Move to folder, Favorite, Share, Save to device, Open
  with tool…, and Delete. Delete leaves a snackbar with Undo.
- Sort sheet: Newest, Oldest, Name A–Z, Largest. The choice is remembered.
- Empty states: no documents ("Scan or import to get started"), no results ("No matches for
  'rent'. Try another word."), empty folder.

**Document viewer:** pages rendered lazily (PDFium), with a page indicator ("2 / 5") and a
bottom bar of Share, Tools and Info. An Info sheet shows format, size, pages, created and
modified dates, and the folder. Images use a zoomable viewer.

### 6.4 Tools hub

Grouped grid with `SectionHeader`s: **PDF** (Merge, Split, Organize, Compress PDF, PDF →
Images, Images → PDF), **Image** (Photo crop, Compress image, Resize), **Text** (Extract
text), and **Convert** (the registry list grouped by `ConversionCategory`, each row
"DOCX → TXT" with a fidelity pill).

All tools share one layout pattern:

```
┌─────────────────────────────────────┐
│ ‹←›  Compress image                 │
│ ① Choose file   [Pick photo]        │
│ ② Options       ...tool-specific... │
│ ③ Preview       before → after      │
│ ⚠ FidelityNote (if lossy/convert)   │
│                                     │
│            [Compress & save]        │  ← sticky bottom action
└─────────────────────────────────────┘
```

| Tool | Specific UI |
|---|---|
| **Photo crop (presets)** | Preset chips: Passport 35×45 mm, US 2×2 in, China visa 33×48 mm, Stamp 20×25 mm, ID card, A4, Letter, Square, 4×6 in, and Custom. A fixed-aspect crop frame that pans and zooms. Shows "Output 413 × 531 px at 300 DPI". A note: "Sizes vary by country. Check the official photo rules." Optional rotate. Output JPG/PNG. |
| **Compress image** | Mode: *Quality* slider **or** *Target size* field ("under [200] KB"). Optional max dimension. Live before/after size: "2.4 MB → 186 KB (−92%)". If the target can't be met: "Smallest possible is 240 KB. Try resizing." |
| **Resize image** | Width/height with aspect lock, percentage presets (25/50/75%), and common pixel presets. |
| **Merge PDFs** | Pick 2 or more files, drag to reorder, show total pages. Name the output. |
| **Split PDF** | Modes: range ("1-3, 5"), every N pages, or pick pages from thumbnails. Output as one file or several. |
| **Organize PDF** | Thumbnail grid: drag to reorder, tap to select, then rotate or delete. Save a copy. |
| **Compress PDF** | Level: Light, Recommended, Strong (with hints). **Warning:** "Pages are saved as images. Text won't be selectable." Before/after size. |
| **PDF → Images** | JPG/PNG, resolution (Standard 150 DPI / High 300 DPI), page selection. |
| **Images → PDF** | Pick photos, reorder, page size, quality. |
| **Extract text (OCR)** | Pick an image or PDF, choose a script, then review in an editable text field with the source preview above (switchable). Actions: Copy, Share text, Save TXT, Save DOCX. |
| **Convert** | Pick a spec, pick input(s) filtered to accepted formats, see the FidelityNote and limitations, run, then preview and save. |

States for every tool: *idle* (step 1 highlighted), *picking*, *ready*, *processing*
(ProgressPanel, cancellable), *success* (sheet with size and actions), and *error*
(FailureView with a recovery hint; inputs untouched).

### 6.5 Settings

Sections:
- **Appearance:** Theme (Match system · Light · Dark).
- **Scanning:** default filter, auto-detect edges, default quality, default page size, searchable PDF.
- **Text recognition:** OCR language (script) with an availability pill ("On device" / "Not installed").
- **Storage:** usage bar (Documents / Originals / Temporary), with (Clear temporary files).
- **Privacy:** "What stays on your phone" page.
- **About:** version, open-source licenses, and "Scans are copies, not certified originals."

## 7. Content and voice

A friendly, clear expert: short sentences, active voice, sentence case. Name the user's
goal, not the mechanism.

| Do | Don't |
|---|---|
| "Saved · 3 pages · 612 KB" | "Operation completed successfully" |
| "Couldn't open this file. It may be damaged. Try another copy." | "Error: PdfException code 3" |
| "Pages are saved as images. Text won't be selectable." | "Optimizing PDF…" (hides the trade-off) |
| "Convert to Word (layout may change)" | "Perfect PDF to Word" |
| "Make text searchable" | "AI-powered OCR magic" |
| "Your documents stay on this phone." | "Military-grade security" |
| "Sizes vary by country. Check the official photo rules." | "Guaranteed passport-compliant" |
| "Scans are copies, not certified originals." | "Legally valid scan" |

- Buttons are verbs: "Save PDF", "Compress & save", "Merge".
- Numbers are human: "1.4 MB", "Yesterday", "Page 2 of 5".
- Errors follow the pattern *what happened* + *what to do*, from `FailureCode.title` and `.recovery`.

## 8. Accessibility (WCAG 2.2 AA)

- **Contrast:** see §4.1; the token pairs listed there are checked.
- **Targets:** at least 48 × 48 dp (`IconButton` theme minimum 48; buttons 52 high). Crop
  handles have 48 dp hit areas.
- **Text scaling:** layouts work at 200%. Tool tiles grow vertically; the page tray scrolls horizontally.
- **Screen readers:** every icon button has a `tooltip` or `Semantics(label)`. Page thumbnails
  are announced as "Page 2 of 5, grayscale", with custom actions "Move left" and "Move right"
  so reordering doesn't need dragging. Crop handles expose "Top-left corner", with increase
  and decrease actions that nudge by 1%.
- **Headers:** `SectionHeader` sets `Semantics(header: true)`.
- **Motion:** honor reduce-motion. No auto-playing animation.
- **Status:** success and error use an icon + text, never color alone.
- **Focus order:** follows the visual order. Dialogs trap focus and return it to the trigger.

## 9. Responsive rules

| Width | Layout |
|---|---|
| < 600 dp (phone) | Bottom nav; tool grid 2 columns; full-screen sheets for options |
| 600–839 dp | Rail without labels; tool grid 3 columns |
| ≥ 840 dp (tablet/web) | Rail with labels; Files is list + preview; tool grid 4 columns; max content width 960 dp |

Landscape on phones: the review screen puts the page tray in a vertical rail on the right.

## 10. Performance UX budgets

| Interaction | Budget | Technique |
|---|---|---|
| Cold start → Home interactive | < 1.5 s mid-tier | Lazy providers; DB opened in the background |
| Tab switch | < 100 ms | StatefulShellRoute keeps tab state |
| Filter preview | < 300 ms | Thumbnails (≤ 480 px) rendered in an isolate |
| Page render on save | < 1.2 s/page (Balanced) | `runHeavy` isolate; progress per page |
| Thumbnails in lists | No jank at 60 fps | `cacheWidth` decoding; stored 360 px thumbnails |
| Anything > 400 ms | Shows a ProgressPanel | Never block input without feedback |

## 11. Theming checklist for new UI

- [ ] Uses `context.colors` / `context.ds` / `context.text` only; no raw hex values.
- [ ] Checked in light and dark, at 100% and 200% text scale.
- [ ] Has empty, loading, error and success states.
- [ ] Primary action is reachable with a thumb and labeled with a verb.
- [ ] Lossy or approximate operations show a `FidelityNote` before running.
- [ ] Copy follows §7.
