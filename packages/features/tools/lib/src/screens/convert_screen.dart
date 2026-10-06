import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Every registered conversion, grouped by category.
class ConvertListScreen extends ConsumerWidget {
  const ConvertListScreen({super.key, this.initialDocId});

  /// When set, only conversions accepting this document are listed.
  final String? initialDocId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(conversionSpecsProvider);
    final doc = initialDocId == null
        ? null
        : ref.watch(documentByIdProvider(initialDocId!)).value;
    final specs = doc == null
        ? all
        : all.where((s) => s.inputs.contains(doc.format)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Convert files')),
      // Free build only; empty otherwise (ADR-0013).
      bottomNavigationBar: const AdBannerSlot(),
      body: specs.isEmpty
          ? const EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'No converters available',
              message: 'No conversion fits this file yet.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.x10),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Text(
                    doc == null
                        ? 'Every conversion runs on this device. Each one '
                              'tells you what it keeps and what may change.'
                        : 'Ways to convert "${doc.name}".',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ),
                for (final cat in ConversionCategory.values)
                  if (specs.any((s) => s.category == cat)) ...[
                    SectionHeader(cat.label),
                    for (final s in specs.where((s) => s.category == cat))
                      _SpecTile(spec: s, docId: initialDocId),
                  ],
              ],
            ),
    );
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.spec, this.docId});

  final ConversionSpec spec;
  final String? docId;

  @override
  Widget build(BuildContext context) {
    final v = formatVisual(context, spec.output);
    return ListTile(
      leading: IconBadge(v.icon, color: v.color),
      title: Text(spec.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Space.x1),
        child: Wrap(
          spacing: Space.x2,
          runSpacing: Space.x1,
          children: [
            Pill(specArrow(spec)),
            Pill(
              spec.fidelity.label,
              background: context.colors.surfaceContainerHigh,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(Routes.convert(spec.id, docId: docId)),
    );
  }
}

/// Runs one conversion described by its [ConversionSpec].
class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({required this.specId, super.key, this.initialDocId});

  final String specId;
  final String? initialDocId;

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen>
    with PreselectDocument {
  var _inputs = <ToolInput>[];
  PdfPageSize _pageSize = PdfPageSize.a4;

  ConversionSpec? get _spec {
    for (final s in ref.read(conversionSpecsProvider)) {
      if (s.id == widget.specId) return s;
    }
    return null;
  }

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => _spec?.inputs ?? const {};
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    if (spec == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Convert')),
        body: const EmptyState(
          icon: Icons.help_outline_rounded,
          title: 'Converter not found',
          message: 'This conversion is not available in this version.',
        ),
      );
    }
    final jobKey = 'convert:${spec.id}';
    final pdfOut = spec.output == DocumentFormat.pdf;
    return ToolScaffold(
      jobKey: jobKey,
      title: spec.title,
      description: '${specArrow(spec)} · runs on this device.',
      primaryLabel: 'Convert',
      primaryIcon: Icons.swap_horiz_rounded,
      onPrimary: _inputs.isEmpty ? null : () => _run(spec, jobKey),
      children: [
        FidelityNote(
          label: spec.fidelity.label,
          explanation: spec.fidelity.explanation,
          limitations: spec.limitations,
        ),
        InputPicker(
          accepts: spec.inputs,
          inputs: _inputs,
          multiple: spec.multipleInputs,
          reorderable: spec.multipleInputs,
          onChanged: (v) => setState(() => _inputs = v),
        ),
        if (pdfOut)
          ChoiceGroup<PdfPageSize>(
            label: 'Page size',
            values: PdfPageSize.values,
            selected: _pageSize,
            labelOf: (s) => s.label,
            onSelected: (s) => setState(() => _pageSize = s),
          ),
      ],
    );
  }

  void _run(ConversionSpec spec, String jobKey) {
    final request = ConversionRequest(
      specId: spec.id,
      inputs: [
        for (final i in _inputs)
          ConversionInput(path: i.path, name: i.name, format: i.format),
      ],
      options: {
        if (spec.output == DocumentFormat.pdf) 'pageSize': _pageSize.name,
      },
    );
    final engine = ref.read(conversionEngineProvider);
    ref
        .read(jobProvider(jobKey).notifier)
        .start(
          (report) => engine.convert(request, onProgress: report),
          label: 'Converting…',
        );
  }
}
