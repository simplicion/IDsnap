import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:feature_scan/src/widgets/page_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter picker with live swatches of the current page, plus brightness and
/// contrast. Edits are parameters, so "Reset" always restores the original.
class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({required this.pageId, super.key});

  final String pageId;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  double? _brightness;
  double? _contrast;

  @override
  Widget build(BuildContext context) {
    final pages =
        ref.watch(scanSessionProvider).value?.pages ?? const <ScanPage>[];
    final page = pages.where((p) => p.id == widget.pageId).firstOrNull;
    if (page == null) return const SizedBox(height: 120);
    final session = ref.read(scanSessionProvider.notifier);
    final edits = page.edits;
    final brightness = _brightness ?? edits.brightness;
    final contrast = _contrast ?? edits.contrast;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Filters', style: context.text.titleMedium),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() {
                        _brightness = 0;
                        _contrast = 0;
                      });
                      await session.setFilter(
                        page.id,
                        EnhancementFilter.original,
                      );
                      await session.setAdjustments(
                        page.id,
                        brightness: 0,
                        contrast: 0,
                      );
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 148,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                children: [
                  for (final f in EnhancementFilter.values)
                    _Swatch(
                      page: page,
                      filter: f,
                      selected: edits.filter == f,
                      onTap: () => session.setFilter(page.id, f),
                    ),
                ],
              ),
            ),
            _SliderRow(
              icon: Icons.brightness_6_outlined,
              label: 'Brightness',
              value: brightness,
              onChanged: (v) => setState(() => _brightness = v),
              onChangeEnd: (v) =>
                  session.setAdjustments(page.id, brightness: v),
            ),
            _SliderRow(
              icon: Icons.contrast_rounded,
              label: 'Contrast',
              value: contrast,
              onChanged: (v) => setState(() => _contrast = v),
              onChangeEnd: (v) => session.setAdjustments(page.id, contrast: v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.x2,
                Space.gutter,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: pages.length < 2
                          ? null
                          : () async {
                              await session.applyToAll(
                                edits.filter,
                                brightness: brightness,
                                contrast: contrast,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                showAppSnack(
                                  context,
                                  'Applied to all ${pages.length} pages',
                                );
                              }
                            },
                      child: const Text('Apply to all pages'),
                    ),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.page,
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final ScanPage page;
  final EnhancementFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${filter.label} filter',
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.buttonAll,
          child: SizedBox(
            width: 84,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: Motion.fast,
                  height: 104,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: Radii.buttonAll,
                    border: Border.all(
                      color: selected ? scheme.primary : context.ds.border,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(Radii.button - 2),
                    ),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: PageImage(
                        page: page,
                        size: PageImageSize.thumb,
                        fit: BoxFit.cover,
                        edits: page.edits.copyWith(filter: filter),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  filter.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(
                    color: selected ? scheme.primary : null,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Space.gutter, right: Space.x2),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.ds.textSecondary),
        const SizedBox(width: Space.x2),
        SizedBox(width: 84, child: Text(label, style: context.text.bodyMedium)),
        Expanded(
          child: Slider(
            value: value.clamp(-1, 1),
            min: -1,
            divisions: 40,
            label: (value * 100).round().toString(),
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    ),
  );
}
