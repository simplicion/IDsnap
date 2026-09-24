import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Set<DocumentFormat> _imageFormats = {
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.bmp,
  DocumentFormat.gif,
  DocumentFormat.tiff,
};

class ImagesToPdfScreen extends ConsumerStatefulWidget {
  const ImagesToPdfScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends ConsumerState<ImagesToPdfScreen>
    with PreselectDocument {
  static const _job = 'images-to-pdf';
  var _inputs = <ToolInput>[];
  PdfPageSize? _pageSize;
  QualityPreset? _quality;
  final _name = TextEditingController(text: 'Images');

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => _imageFormats;
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final pageSize = _pageSize ?? settings.pageSize;
    final quality = _quality ?? settings.quality;
    final n = _inputs.length;
    return ToolScaffold(
      jobKey: _job,
      title: 'Images to PDF',
      description:
          'Turn photos into a single PDF — one image per page, in the order '
          'you choose.',
      primaryLabel: n == 0
          ? 'Create PDF'
          : 'Create PDF ($n page${n == 1 ? '' : 's'})',
      primaryIcon: Icons.picture_as_pdf_rounded,
      onPrimary: n == 0 ? null : () => _run(pageSize, quality),
      children: [
        InputPicker(
          accepts: _imageFormats,
          inputs: _inputs,
          multiple: true,
          reorderable: true,
          title: 'Images',
          onChanged: (v) => setState(() => _inputs = v),
        ),
        ChoiceGroup<PdfPageSize>(
          label: 'Page size',
          values: PdfPageSize.values,
          selected: pageSize,
          labelOf: (s) => s.label,
          onSelected: (s) => setState(() => _pageSize = s),
        ),
        ChoiceGroup<QualityPreset>(
          label: 'Quality',
          hint: quality.hint,
          values: QualityPreset.values,
          selected: quality,
          labelOf: (q) => q.label,
          onSelected: (q) => setState(() => _quality = q),
        ),
        OutputNameField(controller: _name),
      ],
    );
  }

  void _run(PdfPageSize pageSize, QualityPreset quality) {
    final inputs = [..._inputs];
    final name = _name.text.trim().isEmpty ? 'Images' : _name.text.trim();
    final files = ref.read(fileStoreProvider);
    final images = ref.read(imageProcessorProvider);
    final pdf = ref.read(pdfEngineProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final pages = <Uint8List>[];
      for (final (i, input) in inputs.indexed) {
        final bytes = await files.read(input.path);
        final page = await images.renderPage(
          bytes,
          const PageEdits(filter: EnhancementFilter.original),
          preset: quality,
        );
        if (page case Err(:final failure)) {
          return Err(AppFailure(failure.code, detail: input.fileLabel));
        }
        pages.add(page.valueOrNull!);
        report((i + 1) / inputs.length * 0.9);
      }
      final out = await pdf.fromImages(
        pages,
        PdfBuildOptions(pageSize: pageSize),
      );
      return out.map(
        (b) => [
          OutputFile(
            bytes: b,
            format: DocumentFormat.pdf,
            suggestedName: name,
            expectedPages: pages.length,
          ),
        ],
      );
    }, label: 'Building PDF…');
  }
}
