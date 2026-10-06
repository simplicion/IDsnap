import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "PDF · 3 pages · 1.2 MB"
String documentMeta(Document d) => [
  d.format.label.replaceAll(' image', ''),
  if (d.pageCount != null)
    '${d.pageCount} ${d.pageCount == 1 ? 'page' : 'pages'}',
  formatBytes(d.sizeBytes),
].join(' · ');

/// Whether the vault PDF at [relativePath] needs a password to open, e.g.
/// one saved by Protect file. Cached for the session; false when it can't be
/// checked. Only worth asking for PDFs without a thumbnail: a protected PDF
/// can't be rendered when it is saved, so it never has one.
final pdfNeedsPasswordProvider = FutureProvider.family<bool, String>((
  ref,
  relativePath,
) async {
  try {
    final protector = ref.watch(pdfProtectorProvider);
    final files = ref.watch(fileStoreProvider);
    final plain = ref.watch(plainFileAccessProvider);
    final path = await plain.decryptToTemp(files.absolute(relativePath));
    try {
      return (await protector.needsPassword(path)).valueOrNull ?? false;
    } finally {
      await plain.releaseTemp(path);
    }
  } on Object {
    return false; // Not wired (tests, previews) or unreadable.
  }
});

/// Whether [doc] is a password-protected PDF (see [pdfNeedsPasswordProvider]).
bool isPasswordProtected(WidgetRef ref, Document doc) =>
    doc.format == DocumentFormat.pdf &&
    doc.thumbnailPath == null &&
    (ref.watch(pdfNeedsPasswordProvider(doc.relativePath)).value ?? false);

/// Small lock shown next to a password-protected document's name.
class ProtectedBadge extends StatelessWidget {
  const ProtectedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.lock_rounded,
    key: const ValueKey('protected-badge'),
    size: size,
    color: context.ds.textSecondary,
    semanticLabel: 'Password-protected',
  );
}

/// Thumbnail if one exists, otherwise the format icon (a locked PDF for
/// password-protected PDFs).
class DocumentThumb extends ConsumerWidget {
  const DocumentThumb(this.doc, {super.key, this.size = 56});

  final Document doc;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visual = formatVisual(context, doc.format);
    final fallback = Center(
      child: IconBadge(visual.icon, color: visual.color, size: size * 0.8),
    );
    final thumb = doc.thumbnailPath;
    if (thumb == null) {
      if (isPasswordProtected(ref, doc)) {
        return SizedBox(
          key: const ValueKey('locked-pdf-thumb'),
          width: size,
          height: size,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconBadge(visual.icon, color: visual.color, size: size * 0.8),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(
                    radius: size * 0.16,
                    backgroundColor: context.colors.surface,
                    child: Icon(
                      Icons.lock_rounded,
                      size: size * 0.2,
                      color: visual.color,
                      semanticLabel: 'Password-protected PDF',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return SizedBox(width: size, height: size, child: fallback);
    }
    // Thumbnails are encrypted at rest (ADR-0010): decrypted in memory.
    final bytes = ref.watch(vaultImageBytesProvider(thumb)).value;
    return ClipRRect(
      borderRadius: Radii.smAll,
      child: Container(
        width: size,
        height: size,
        color: context.colors.surfaceContainerHigh,
        child: bytes == null
            ? fallback
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class DocumentListTile extends StatelessWidget {
  const DocumentListTile({
    required this.doc,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    super.key,
  });

  final Document doc;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: context.colors.primaryContainer.withValues(alpha: 0.5),
      leading: selecting
          ? SizedBox(
              width: 56,
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? context.colors.primary
                    : context.ds.textSecondary,
              ),
            )
          : DocumentThumb(doc),
      title: Row(
        children: [
          Flexible(
            child: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Consumer(
            builder: (context, ref, _) => isPasswordProtected(ref, doc)
                ? const Padding(
                    padding: EdgeInsets.only(left: Space.x1),
                    child: ProtectedBadge(),
                  )
                : const SizedBox.shrink(),
          ),
          if (doc.favorite) ...[
            const SizedBox(width: Space.x1),
            Icon(
              Icons.star_rounded,
              size: 16,
              color: context.colors.tertiary,
              semanticLabel: 'Favorite',
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${documentMeta(doc)}\n${formatRelativeDate(doc.updatedAt)}',
        style: context.text.bodySmall?.copyWith(
          color: context.ds.textSecondary,
        ),
      ),
      isThreeLine: true,
      trailing: selecting
          ? null
          : IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More actions for ${doc.name}',
              onPressed: onMore,
            ),
    ),
  );
}

class DocumentGridTile extends StatelessWidget {
  const DocumentGridTile({
    required this.doc,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Document doc;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    label: doc.name,
    child: Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: BorderSide(
          color: selected ? context.colors.primary : context.ds.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: context.colors.surfaceContainerHigh,
                    child: LayoutBuilder(
                      builder: (context, c) =>
                          DocumentThumb(doc, size: c.biggest.shortestSide),
                    ),
                  ),
                  if (selecting)
                    Positioned(
                      top: Space.x2,
                      right: Space.x2,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? context.colors.primary
                            : context.colors.onSurface,
                      ),
                    ),
                  if (doc.favorite && !selecting)
                    Positioned(
                      top: Space.x2,
                      right: Space.x2,
                      child: Icon(
                        Icons.star_rounded,
                        color: context.colors.tertiary,
                        semanticLabel: 'Favorite',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          doc.name,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) =>
                            isPasswordProtected(ref, doc)
                            ? const Padding(
                                padding: EdgeInsets.only(left: Space.x1),
                                child: ProtectedBadge(size: 14),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    documentMeta(doc),
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
