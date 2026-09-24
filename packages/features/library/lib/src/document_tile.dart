import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
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

/// Thumbnail if one exists, otherwise the format icon.
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
      return SizedBox(width: size, height: size, child: fallback);
    }
    final path = ref.watch(fileStoreProvider).absolute(thumb);
    return ClipRRect(
      borderRadius: Radii.smAll,
      child: Container(
        width: size,
        height: size,
        color: context.colors.surfaceContainerHigh,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
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
                  Text(
                    doc.name,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
