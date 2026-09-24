import 'dart:convert';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Set<DocumentFormat> ocrInputs = {
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.bmp,
  DocumentFormat.pdf,
};

class _PageText {
  _PageText(this.title, String text, {required this.fromPdfText})
    : controller = TextEditingController(text: text);

  final String title;

  /// True when the text came from the PDF itself rather than OCR.
  final bool fromPdfText;
  final TextEditingController controller;
}

class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> with PreselectDocument {
  static const _job = 'ocr';
  var _inputs = <ToolInput>[];
  OcrScript? _script;
  List<_PageText>? _results;
  bool _running = false;
  double? _progress;
  AppFailure? _failure;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => ocrInputs;
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    for (final r in _results ?? <_PageText>[]) {
      r.controller.dispose();
    }
    super.dispose();
  }

  String get _allText => [
    for (final r in _results ?? <_PageText>[]) r.controller.text.trim(),
  ].where((t) => t.isNotEmpty).join('\n\n');

  String get _baseName => _inputs.firstOrNull?.name ?? 'Extracted text';

  @override
  Widget build(BuildContext context) {
    final script = _script ?? ref.watch(currentSettingsProvider).ocrScript;
    if (_running) {
      return Scaffold(
        appBar: AppBar(title: const Text('Extract text')),
        body: ProgressPanel(label: 'Reading text…', progress: _progress),
      );
    }
    final results = _results;
    final docxSpec = _docxSpec();
    return ToolScaffold(
      jobKey: _job,
      title: 'Extract text',
      description:
          'Recognize text in photos and scanned PDFs, right on your phone. '
          'Edit it, copy it, or save it as a file.',
      primaryLabel: results == null ? 'Recognize text' : null,
      primaryIcon: Icons.text_snippet_rounded,
      onPrimary: _inputs.isEmpty ? null : () => _recognize(script),
      actions: [
        if (results != null)
          IconButton(
            tooltip: 'Start over',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => setState(() => _results = null),
          ),
      ],
      children: results == null
          ? [
              InputPicker(
                accepts: ocrInputs,
                inputs: _inputs,
                multiple: true,
                reorderable: true,
                title: 'Photos or a PDF',
                onChanged: (v) => setState(() => _inputs = v),
              ),
              ChoiceGroup<OcrScript>(
                label: 'Language / script',
                values: OcrScript.values,
                selected: script,
                labelOf: (s) => s.label.split(' (').first,
                onSelected: (s) => setState(() => _script = s),
              ),
              _CapabilityNote(script: script),
              if (_failure != null) FailureView(_failure!),
            ]
          : [
              const FidelityNote(
                label: 'Review before use',
                explanation:
                    'Recognition can make mistakes — review before use, '
                    'especially names, numbers and dates.',
              ),
              if (results.every((r) => r.controller.text.trim().isEmpty))
                const EmptyState(
                  icon: Icons.text_fields_rounded,
                  title: 'No text found',
                  message:
                      'Try a sharper photo with more light, or choose the '
                      'right language.',
                ),
              _ActionBar(
                onCopy: _copy,
                onShare: _share,
                onSaveTxt: _saveTxt,
                onSaveDocx: docxSpec == null ? null : () => _saveDocx(docxSpec),
              ),
              for (final r in results)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.title, style: context.text.titleSmall),
                        ),
                        if (r.fromPdfText)
                          const Pill('Text from PDF')
                        else
                          const Pill('Recognized'),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    TextField(
                      controller: r.controller,
                      minLines: 3,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: 'No text on this page',
                      ),
                    ),
                  ],
                ),
            ],
    );
  }

  ConversionSpec? _docxSpec() {
    for (final s in ref.watch(conversionSpecsProvider)) {
      if (s.inputs.contains(DocumentFormat.txt) &&
          s.output == DocumentFormat.docx) {
        return s;
      }
    }
    return null;
  }

  Future<void> _recognize(OcrScript script) async {
    final ocr = ref.read(textRecognizerProvider);
    final pdf = ref.read(pdfEngineProvider);
    final files = ref.read(fileStoreProvider);
    final inputs = [..._inputs];
    setState(() {
      _running = true;
      _progress = null;
      _failure = null;
    });

    final pages = <_PageText>[];
    AppFailure? failure;
    try {
      for (final (i, input) in inputs.indexed) {
        if (input.format == DocumentFormat.pdf) {
          final r = await _readPdf(input, script, ocr, pdf, files);
          if (r case Err(failure: final f)) {
            failure = f;
            break;
          }
          pages.addAll(r.valueOrNull!);
        } else {
          final r = await ocr.recognize(input.path, script);
          if (r case Err(failure: final f)) {
            failure = AppFailure(f.code, detail: input.fileLabel);
            break;
          }
          pages.add(
            _PageText(
              inputs.length == 1
                  ? input.fileLabel
                  : '${i + 1}. ${input.fileLabel}',
              r.valueOrNull!.text,
              fromPdfText: false,
            ),
          );
        }
        if (mounted) setState(() => _progress = (i + 1) / inputs.length);
      }
    } on Object catch (e, st) {
      failure = AppFailure(FailureCode.unknown, cause: e, stackTrace: st);
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      if (failure != null) {
        _failure = failure;
        for (final p in pages) {
          p.controller.dispose();
        }
      } else {
        _results = pages;
      }
    });
  }

  Future<Result<List<_PageText>>> _readPdf(
    ToolInput input,
    OcrScript script,
    TextRecognizer ocr,
    PdfEngine pdf,
    FileStore files,
  ) async {
    final embedded = await pdf.extractText(input.path);
    if (embedded case Err(:final failure)) return Err(failure);
    final texts = embedded.valueOrNull!;
    final out = <_PageText>[];
    for (final (i, text) in texts.indexed) {
      final title = '${input.name} · page ${i + 1}';
      if (text.trim().isNotEmpty) {
        out.add(_PageText(title, text, fromPdfText: true));
        continue;
      }
      final png = await pdf.renderPage(input.path, i, targetWidth: 2000);
      if (png case Err(:final failure)) return Err(failure);
      final temp = await files.writeTemp(png.valueOrNull!, 'png');
      try {
        final r = await ocr.recognize(temp, script);
        if (r case Err(:final failure)) return Err(failure);
        out.add(_PageText(title, r.valueOrNull!.text, fromPdfText: false));
      } finally {
        await files.delete(temp);
      }
      if (mounted) setState(() => _progress = (i + 1) / texts.length);
    }
    return Ok(out);
  }

  Future<void> _copy() async {
    final r = await ref.read(shareServiceProvider).copyText(_allText);
    if (!mounted) return;
    r.fold(
      (_) => showAppSnack(context, 'Text copied'),
      (f) => showFailureSnack(context, f),
    );
  }

  Future<void> _share() async {
    final r = await ref.read(shareServiceProvider).shareText(_allText);
    if (!mounted) return;
    if (r case Err(:final failure)) showFailureSnack(context, failure);
  }

  void _saveTxt() {
    final text = _allText;
    final name = _baseName;
    ref
        .read(jobProvider(_job).notifier)
        .start(
          (report) async => Ok([
            OutputFile(
              bytes: utf8.encode(text),
              format: DocumentFormat.txt,
              suggestedName: '$name (text)',
            ),
          ]),
          label: 'Saving text…',
        );
  }

  void _saveDocx(ConversionSpec spec) {
    final text = _allText;
    final name = _baseName;
    final files = ref.read(fileStoreProvider);
    final engine = ref.read(conversionEngineProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final temp = await files.writeTemp(utf8.encode(text), 'txt');
      try {
        return await engine.convert(
          ConversionRequest(
            specId: spec.id,
            inputs: [
              ConversionInput(
                path: temp,
                name: '$name (text)',
                format: DocumentFormat.txt,
              ),
            ],
          ),
          onProgress: report,
        );
      } finally {
        await files.delete(temp);
      }
    }, label: 'Creating Word document…');
  }
}

class _CapabilityNote extends ConsumerWidget {
  const _CapabilityNote({required this.script});

  final OcrScript script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(ocrCapabilityProvider(script)).value;
    if (cap == null || (cap.available && !cap.requiresDownload)) {
      return const SizedBox.shrink();
    }
    return FidelityNote(
      label: cap.available ? 'One-time setup' : 'Not available on this device',
      explanation:
          cap.note ??
          (cap.available
              ? 'This language model downloads once, then works offline.'
              : "This language isn't installed on this device yet."),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onCopy,
    required this.onShare,
    required this.onSaveTxt,
    required this.onSaveDocx,
  });

  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onSaveTxt;
  final VoidCallback? onSaveDocx;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.x2,
    runSpacing: Space.x2,
    children: [
      FilledButton.tonalIcon(
        onPressed: onCopy,
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copy'),
      ),
      FilledButton.tonalIcon(
        onPressed: onShare,
        icon: const Icon(Icons.ios_share_rounded),
        label: const Text('Share'),
      ),
      OutlinedButton.icon(
        onPressed: onSaveTxt,
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('Save as TXT'),
      ),
      if (onSaveDocx != null)
        OutlinedButton.icon(
          onPressed: onSaveDocx,
          icon: const Icon(Icons.description_rounded),
          label: const Text('Save as Word'),
        ),
    ],
  );
}
