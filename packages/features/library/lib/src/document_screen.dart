import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_actions.dart';
import 'package:feature_library/src/document_tile.dart';
import 'package:feature_library/src/folders/folder_lock.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:feature_library/src/folders/folder_visuals.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Viewer for one library document with share/rename/move/delete actions and
/// shortcuts into tools.
class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentByIdProvider(documentId));
    final hidden = ref.watch(pendingDeletesProvider).contains(documentId);
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: FailureView(
          AppFailure(
            FailureCode.unknown,
            cause: e,
            message:
                "This document couldn't be opened. It is still on this phone "
                '— try again, or go back to ID Vault.',
          ),
          onRetry: () => ref.invalidate(documentByIdProvider(documentId)),
        ),
      ),
      data: (doc) => doc == null || hidden
          ? Scaffold(
              appBar: AppBar(),
              body: const FailureView(AppFailure(FailureCode.notFound)),
            )
          : _LockGuard(doc: doc),
    );
  }
}

/// A document inside a locked folder is shown only while that folder is
/// unlocked (e.g. when opened from a link or a stale screen).
class _LockGuard extends ConsumerWidget {
  const _LockGuard({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(folderTreeProvider).value;
    if (tree == null && doc.folderId != null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final underLock = tree != null && tree.locksOnPath(doc.folderId).isNotEmpty;
    if (underLock && !canOpenFolder(ref, doc.folderId)) {
      return Scaffold(
        appBar: AppBar(),
        body: LockedFolderView(
          name: tree.locksOnPath(doc.folderId).first.name,
          onUnlock: () => ensureFolderAccess(context, ref, doc.folderId),
        ),
      );
    }
    return FolderSecureScope(
      active: underLock,
      child: _DocumentView(doc: doc),
    );
  }
}

class _DocumentView extends ConsumerWidget {
  const _DocumentView({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = DocumentActions(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: doc.favorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: Icon(
              doc.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            color: doc.favorite ? context.colors.tertiary : null,
            onPressed: () => actions.toggleFavorite(context, doc),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => actions.share(context, [doc]),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) => _onMenu(context, ref, actions, v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'protect',
                child: _ProLabel(
                  'Protect & share',
                  feature: ProFeature.protectFile,
                ),
              ),
              if (isPasswordProtected(ref, doc))
                const PopupMenuItem(
                  value: 'removePassword',
                  child: Text('Remove password…'),
                ),
              const PopupMenuItem(value: 'save', child: Text('Save to device')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'move', child: Text('Move to folder')),
              PopupMenuItem(
                value: 'expiry',
                child: Text(
                  doc.expiresAt == null ? 'Add expiry date' : 'Change expiry',
                ),
              ),
              if (doc.expiresAt != null)
                const PopupMenuItem(
                  value: 'clearExpiry',
                  child: Text('Remove expiry date'),
                ),
              const PopupMenuItem(value: 'details', child: Text('Details')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _Preview(doc: doc)),
          _VaultInfo(doc: doc, actions: actions),
          _ToolShortcuts(doc: doc),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    DocumentActions actions,
    String value,
  ) async {
    switch (value) {
      case 'protect':
        await actions.protectAndShare(context, doc);
      case 'removePassword':
        // Free tool: writes an unprotected copy; this document is unchanged.
        await context.push<void>(
          Routes.tool(ToolId.removePdfPassword, docId: doc.id),
        );
      case 'save':
        await actions.saveToDevice(context, doc);
      case 'rename':
        await actions.rename(context, doc);
      case 'move':
        await actions.moveToFolder(context, [doc]);
      case 'expiry':
        await actions.setExpiry(context, doc);
      case 'clearExpiry':
        await actions.clearExpiry(context, doc);
      case 'details':
        await showModalBottomSheet<void>(
          context: context,
          builder: (_) => _DetailsSheet(doc: doc),
        );
      case 'delete':
        final deleted = await actions.delete(context, [doc]);
        if (deleted && context.mounted) context.pop();
    }
  }
}

/// Folder and expiry chips (roadmap B1/B4).
class _VaultInfo extends StatelessWidget {
  const _VaultInfo({required this.doc, required this.actions});

  final Document doc;
  final DocumentActions actions;

  @override
  Widget build(BuildContext context) {
    final expiry = doc.expiresAt;
    final expired = expiry != null && expiry.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        0,
      ),
      child: Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          _FolderChip(doc: doc, actions: actions),
          ActionChip(
            avatar: Icon(
              expired ? Icons.warning_amber_rounded : Icons.event_rounded,
              size: 18,
              color: expired ? context.colors.error : null,
            ),
            label: Text(
              expiry == null
                  ? 'Add expiry date'
                  : '${expired ? 'Expired' : 'Expires'} '
                        '${formatRelativeDateShort(expiry)}',
            ),
            tooltip: 'Expiry date',
            onPressed: () => actions.setExpiry(context, doc),
          ),
        ],
      ),
    );
  }
}

class _FolderChip extends ConsumerWidget {
  const _FolderChip({required this.doc, required this.actions});

  final Document doc;
  final DocumentActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(folderTreeProvider).value;
    final folder = tree?[doc.folderId];
    return ActionChip(
      avatar: Icon(
        folder == null ? Icons.shield_outlined : folderIconData(folder.icon),
        size: 18,
      ),
      label: Text(folder?.name ?? 'ID Vault'),
      tooltip: 'Move to folder',
      onPressed: () => actions.moveToFolder(context, [doc]),
    );
  }
}

/// "12 Mar 2027".
String formatRelativeDateShort(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(fileStoreProvider).absolute(doc.relativePath);
    if (doc.format == DocumentFormat.pdf) {
      return _PdfPages(doc: doc, path: path);
    }
    if (doc.format.isImage) {
      // Decrypted in memory (ADR-0010): vault files are encrypted at rest.
      const broken = FailureView(AppFailure(FailureCode.corruptFile));
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: switch (ref.watch(vaultImageBytesProvider(path))) {
            AsyncData(:final value?) => Image.memory(
              value,
              semanticLabel: doc.name,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => broken,
            ),
            AsyncLoading() => const CircularProgressIndicator(),
            _ => broken,
          },
        ),
      );
    }
    if (doc.format.isText) return _TextPreview(path: path);
    return _InfoPreview(doc: doc);
  }
}

class _TextPreview extends ConsumerStatefulWidget {
  const _TextPreview({required this.path});

  final String path;

  @override
  ConsumerState<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends ConsumerState<_TextPreview> {
  late final Future<String> _text = ref
      .read(fileStoreProvider)
      .readText(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text,
    builder: (context, snap) {
      if (snap.hasError) {
        return const FailureView(AppFailure(FailureCode.corruptFile));
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.gutter),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: SelectableText(snap.data!, style: context.text.bodyLarge),
            ),
          ),
        ),
      );
    },
  );
}

class _InfoPreview extends StatelessWidget {
  const _InfoPreview({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context) {
    final v = formatVisual(context, doc.format);
    return EmptyState(
      icon: v.icon,
      title: doc.format.label,
      message:
          "A preview isn't available for this format. You can share it, save it to your device or convert it with Tools.",
    );
  }
}

/// Lazily renders PDF pages one at a time with pinch-zoom.
///
/// Password-protected PDFs (e.g. saved by Protect file) ask for their
/// password: the vault copy is decrypted to a private temp file, a second
/// temp copy without the PDF password is written with it, and that copy is
/// rendered. Both temp files are removed when the viewer closes; the file in
/// the vault stays protected and the password is never stored.
class _PdfPages extends ConsumerStatefulWidget {
  const _PdfPages({required this.doc, required this.path});

  final Document doc;
  final String path;

  @override
  ConsumerState<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends ConsumerState<_PdfPages> {
  // PDFium needs a real file: a private plaintext copy in the app cache,
  // shredded when the viewer closes (ADR-0010).
  late final PlainFileAccess _access;
  late final FileStore _files;
  late final Future<String> _plain;
  late Future<Result<int>> _count;

  /// Temp copy with the PDF password removed (protected PDFs only).
  String? _unlocked;
  final Map<int, Future<Result<Uint8List>>> _pages = {};
  int _current = 0;
  var _prompted = false;

  @override
  void initState() {
    super.initState();
    _access = ref.read(plainFileAccessProvider);
    _files = ref.read(fileStoreProvider);
    _plain = _access.decryptToTemp(widget.path);
    _count = _open();
  }

  Future<Result<int>> _open() async {
    final String path;
    try {
      path = await _plain;
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    }
    final count = await ref.read(pdfEngineProvider).pageCount(path);
    if (count.failureOrNull?.code == FailureCode.passwordProtected &&
        !_prompted) {
      // Ask straight away once; the panel offers it again after a cancel.
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askPassword());
      });
    }
    return count;
  }

  Future<String> _renderPath() async => _unlocked ?? await _plain;

  Future<Result<Uint8List>> _page(int i, int width) => _pages.putIfAbsent(
    i,
    () async => await ref
        .read(pdfEngineProvider)
        .renderPage(await _renderPath(), i, targetWidth: width),
  );

  /// A fresh temp path for the unlocked copy.
  Future<String> _tempPdfPath() async {
    final probe = await _files.writeTemp(Uint8List(0), 'pdf');
    await _files.delete(probe);
    return probe;
  }

  Future<void> _askPassword() async {
    final PdfProtector protector;
    final String plain;
    try {
      protector = ref.read(pdfProtectorProvider);
      plain = await _plain;
    } on Object catch (e) {
      if (mounted) {
        showFailureSnack(
          context,
          AppFailure(
            FailureCode.passwordProtected,
            cause: e,
            message:
                "Protected PDFs can't be opened on this device. Share the "
                'file and open it in another app.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    String? unlocked;
    final password = await showPdfPasswordPrompt(
      context,
      fileName: widget.doc.fileName,
      action: 'Open',
      message:
          '"${widget.doc.fileName}" is password-protected. Enter its '
          'password to view it. The password is not saved, and the file in '
          'ID Vault stays protected.',
      verify: (pw) async {
        try {
          final out = await _tempPdfPath();
          final r = await protector.removePdfPassword(
            plain,
            pw,
            outputPath: out,
          );
          return r.fold<String?>(
            (file) {
              unlocked = file.path;
              return null;
            },
            (f) => f.code == FailureCode.wrongPassword
                ? "That password isn't right. Check it and try again."
                : '${f.title}. ${f.recovery}',
          );
        } on Object {
          return "The file couldn't be opened. Try again.";
        }
      },
    );
    final path = unlocked;
    if (!mounted) {
      if (path != null) await _deleteQuietly(_files, path);
      return;
    }
    if (password == null || path == null) return; // Cancelled: panel stays.
    final previous = _unlocked;
    if (previous != null) unawaited(_deleteQuietly(_files, previous));
    setState(() {
      _unlocked = path;
      _pages.clear();
      _current = 0;
      _count = ref.read(pdfEngineProvider).pageCount(path);
    });
  }

  static Future<void> _deleteQuietly(FileStore files, String path) async {
    try {
      await files.delete(path);
    } on Object {
      // Leftovers in tmp/ are cleared at the next launch.
    }
  }

  @override
  void dispose() {
    final access = _access;
    unawaited(_plain.then(access.releaseTemp, onError: (Object _) {}));
    final unlocked = _unlocked;
    if (unlocked != null) unawaited(_deleteQuietly(_files, unlocked));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Result<int>>(
    future: _count,
    builder: (context, snap) {
      final result = snap.data;
      if (result == null || snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return result.fold(
        (count) {
          final width =
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .clamp(600, 1600)
                  .round();
          return Stack(
            children: [
              PageView.builder(
                key: ValueKey(_unlocked),
                itemCount: count,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x4),
                    child: FutureBuilder<Result<Uint8List>>(
                      future: _page(i, width),
                      builder: (context, page) {
                        final r = page.data;
                        if (r == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return r.fold(
                          (bytes) => Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Image.memory(
                                bytes,
                                gaplessPlayback: true,
                                semanticLabel: 'Page ${i + 1} of $count',
                              ),
                            ),
                          ),
                          FailureView.new,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: Space.x3,
                left: 0,
                right: 0,
                child: Center(
                  child: Pill(
                    'Page ${_current + 1} of $count',
                    color: context.colors.onInverseSurface,
                    background: context.colors.inverseSurface.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        (failure) {
          if (failure.code == FailureCode.passwordProtected) {
            return _PasswordNeeded(
              onEnter: _askPassword,
              onRemove: () => unawaited(
                context.push(
                  Routes.tool(ToolId.removePdfPassword, docId: widget.doc.id),
                ),
              ),
            );
          }
          return FailureView(failure);
        },
      );
    },
  );
}

/// Shown for a protected PDF until the right password is entered.
class _PasswordNeeded extends StatelessWidget {
  const _PasswordNeeded({required this.onEnter, required this.onRemove});

  final VoidCallback onEnter;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Space.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(
            Icons.lock_rounded,
            color: context.colors.primary,
            size: 72,
          ),
          const SizedBox(height: Space.x4),
          Text(
            'This PDF is password-protected',
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x2),
          Text(
            'Enter its password to view it here. The file in ID Vault stays '
            'protected and the password is not saved.',
            style: context.text.bodyMedium?.copyWith(
              color: context.ds.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x5),
          FilledButton.icon(
            onPressed: onEnter,
            icon: const Icon(Icons.key_rounded),
            label: const Text('Enter password'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Remove password…'),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'Remove password saves an unprotected copy; this file is not '
            'changed.',
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ToolShortcuts extends ConsumerWidget {
  const _ToolShortcuts({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPdf = doc.format == DocumentFormat.pdf;
    final chips = <(IconData, String, ToolId)>[
      if (isPdf || doc.format.isImage)
        (Icons.text_snippet_outlined, 'Extract text', ToolId.ocr),
      if (isPdf) (Icons.draw_rounded, 'Sign', ToolId.signPdf),
      if (isPdf) (Icons.compress_rounded, 'Compress', ToolId.compressPdf),
      if (doc.format.isImage)
        (Icons.compress_rounded, 'Compress', ToolId.compressImage),
      if (doc.format.isImage)
        (Icons.crop_rounded, 'Crop photo', ToolId.photoCrop),
      if (isPdf)
        (Icons.view_carousel_outlined, 'Organize pages', ToolId.organize),
      if (isPdf) (Icons.call_split_rounded, 'Split', ToolId.split),
      (Icons.swap_horiz_rounded, 'Convert', ToolId.convert),
    ];
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.ds.border)),
        ),
        // No fixed height: chips grow with the text size.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.x3,
          ),
          child: Row(
            children: [
              for (final (i, (icon, label, tool)) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: Space.x2),
                _ToolChip(icon: icon, label: label, tool: tool, doc: doc),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A viewer shortcut into a tool; shows the PRO badge when the tool is
/// locked by the policy and asks for Pro before opening it.
class _ToolChip extends ConsumerWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.tool,
    required this.doc,
  });

  final IconData icon;
  final String label;
  final ToolId tool;
  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = Routes.tool(tool, docId: doc.id);
    final feature = proFeatureForLocation(Uri.parse(location));
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: feature == null ? Text(label) : _ProLabel(label, feature: feature),
      onPressed: () => feature == null
          ? unawaited(context.push(location))
          : unawaited(pushIfPro(context, ref, feature, location)),
    );
  }
}

/// [text] followed by a PRO badge while [feature] is locked.
class _ProLabel extends StatelessWidget {
  const _ProLabel(this.text, {required this.feature});

  final String text;
  final ProFeature feature;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(text)),
      const SizedBox(width: Space.x2),
      ProBadge(feature),
    ],
  );
}

class _DetailsSheet extends ConsumerWidget {
  const _DetailsSheet({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(folderTreeProvider).value?.pathTo(doc.folderId);
    String date(DateTime d) =>
        '${formatRelativeDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final rows = <(String, String)>[
      ('Type', doc.format.label),
      ('Size', formatBytes(doc.sizeBytes)),
      if (doc.pageCount != null) ('Pages', '${doc.pageCount}'),
      ('Folder', ['ID Vault', ...?path?.map((f) => f.name)].join(' › ')),
      if (doc.expiresAt != null)
        ('Expires', formatRelativeDateShort(doc.expiresAt!)),
      ('Created', date(doc.createdAt)),
      ('Modified', date(doc.updatedAt)),
      ('Stored', 'On this device only'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DocumentThumb(doc, size: 48),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Text(doc.fileName, style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Space.x4),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        k,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.ds.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(child: Text(v, style: context.text.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
