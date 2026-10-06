import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';

/// Material icon for a [FolderIcons] key (unknown keys → plain folder).
IconData folderIconData(String? key) => switch (key) {
  FolderIcons.badge => Icons.badge_rounded,
  FolderIcons.school => Icons.school_rounded,
  FolderIcons.medical => Icons.medical_services_rounded,
  FolderIcons.car => Icons.directions_car_rounded,
  FolderIcons.receipt => Icons.receipt_long_rounded,
  FolderIcons.home => Icons.home_work_rounded,
  FolderIcons.travel => Icons.flight_rounded,
  FolderIcons.work => Icons.work_rounded,
  FolderIcons.family => Icons.family_restroom_rounded,
  FolderIcons.bank => Icons.account_balance_rounded,
  FolderIcons.pets => Icons.pets_rounded,
  FolderIcons.star => Icons.star_rounded,
  FolderIcons.heart => Icons.favorite_rounded,
  _ => Icons.folder_rounded,
};

/// Accent for a [FolderColors] key; lighter shades in dark mode so the
/// icon keeps enough contrast.
Color folderColor(BuildContext context, String? key) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  Color pick(Color light, Color night) => dark ? night : light;
  return switch (key) {
    FolderColors.blue => pick(Palette.blue600, Palette.blue300),
    FolderColors.purple => pick(
      const Color(0xFF6B3FD4),
      const Color(0xFFB9A2FF),
    ),
    FolderColors.red => pick(Palette.red700, Palette.red300),
    FolderColors.teal => pick(Palette.teal600, Palette.teal300),
    FolderColors.amber => pick(Palette.amber600, Palette.amber300),
    FolderColors.green => pick(Palette.green700, Palette.green300),
    FolderColors.orange => pick(
      const Color(0xFFB54708),
      const Color(0xFFFFB27A),
    ),
    FolderColors.pink => pick(const Color(0xFFB4236B), const Color(0xFFFF9CC8)),
    FolderColors.slate => pick(Palette.slate, Palette.fog),
    _ => context.colors.primary,
  };
}

/// "3 files · 2 folders", "Empty", or "Locked".
String folderStatsLabel(FolderStats? stats, {required bool locked}) {
  if (locked) return 'Locked';
  final s = stats ?? FolderStats.empty;
  if (s.isEmpty) return 'Empty';
  return [
    if (s.documents > 0)
      '${s.documents} ${s.documents == 1 ? 'file' : 'files'}',
    if (s.folders > 0) '${s.folders} ${s.folders == 1 ? 'folder' : 'folders'}',
  ].join(' · ');
}

class FolderBadge extends StatelessWidget {
  const FolderBadge({required this.folder, super.key, this.size = 44});

  final Folder folder;
  final double size;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      IconBadge(
        folderIconData(folder.icon),
        color: folderColor(context, folder.color),
        size: size,
      ),
      if (folder.isLocked)
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.colors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_rounded,
              size: size * 0.36,
              color: context.ds.textSecondary,
            ),
          ),
        ),
    ],
  );
}

class FolderListTile extends StatelessWidget {
  const FolderListTile({
    required this.folder,
    required this.subtitle,
    required this.onTap,
    required this.onMore,
    super.key,
  });

  final Folder folder;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Folder ${folder.name}, $subtitle',
    button: true,
    excludeSemantics: true,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      leading: FolderBadge(folder: folder),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: 'Folder actions',
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: onMore,
      ),
      onTap: onTap,
      onLongPress: onMore,
    ),
  );
}

class FolderGridTile extends StatelessWidget {
  const FolderGridTile({
    required this.folder,
    required this.subtitle,
    required this.onTap,
    required this.onMore,
    super.key,
  });

  final Folder folder;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Folder ${folder.name}, $subtitle',
    button: true,
    excludeSemantics: true,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FolderBadge(folder: folder, size: 36),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Folder actions',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: onMore,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                style: context.text.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
