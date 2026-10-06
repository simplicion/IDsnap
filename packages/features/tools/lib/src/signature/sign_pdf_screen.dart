import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/signature/create_signature.dart';
import 'package:feature_tools/src/signature/signature_pad.dart';
import 'package:feature_tools/src/signature/signature_providers.dart';
import 'package:feature_tools/src/signature/stamp_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A signature or date placed on a page (points, displayed page space).
@immutable
class PlacedStamp {
  const PlacedStamp({
    required this.id,
    required this.pageIndex,
    required this.rect,
    this.image,
    this.text,
  }) : assert((image == null) != (text == null), 'image xor text');

  final int id;
  final int pageIndex;
  final StampRect rect;
  final SignatureImage? image;
  final String? text;

  /// Text stamps are one line; the box height is 1.2 × the font size.
  double get fontSize => rect.height / 1.2;

  PlacedStamp withRect(StampRect r) => PlacedStamp(
    id: id,
    pageIndex: pageIndex,
    rect: r,
    image: image,
    text: text,
  );

  PdfStamp toPdfStamp() => image != null
      ? PdfImageStamp(
          pageIndex: pageIndex,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          png: image!.png,
        )
      : PdfTextStamp(
          pageIndex: pageIndex,
          left: rect.left,
          top: rect.top,
          text: text!,
          fontSize: fontSize,
        );
}

/// Sign PDF (PRD 3.3): pick a PDF, place signatures and dates, save a new
/// signed copy. The original stays unchanged.
class SignPdfScreen extends ConsumerStatefulWidget {
  const SignPdfScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<SignPdfScreen> createState() => _SignPdfScreenState();
}

class _SignPdfScreenState extends ConsumerState<SignPdfScreen>
    with PreselectDocument {
  static const _job = 'sign-pdf';
  var _inputs = <ToolInput>[];
  var _stamps = <PlacedStamp>[];
  StampMethod? _method;
  final _name = TextEditingController();

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  void onPreselected(ToolInput input) => _setInputs([input]);

  void _setInputs(List<ToolInput> v) => setState(() {
    _inputs = v;
    _stamps = [];
    _name.text = v.isEmpty ? '' : '${v.first.name} (signed)';
  });

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _openEditor() async {
    final input = _inputs.firstOrNull;
    if (input == null) return;
    final result = await Navigator.of(context).push<List<PlacedStamp>>(
      MaterialPageRoute(
        builder: (_) =>
            StampEditorScreen(path: input.path, initialStamps: _stamps),
      ),
    );
    if (result != null && mounted) setState(() => _stamps = result);
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final ready = input != null && _stamps.isNotEmpty;
    final pages = {for (final s in _stamps) s.pageIndex + 1}.toList()..sort();
    return ToolScaffold(
      jobKey: _job,
      title: 'Sign PDF',
      description:
          'Add your signature and the date to any page. The original stays '
          'as it is; a signed copy is saved to your library.',
      primaryLabel: input == null
          ? 'Choose a PDF'
          : _stamps.isEmpty
          ? 'Place a signature first'
          : 'Save signed PDF',
      primaryIcon: Icons.draw_rounded,
      onPrimary: ready ? _run : null,
      doneSummary: (_) => _MethodNote(method: _method),
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          title: 'PDF to sign',
          onChanged: _setInputs,
        ),
        if (input != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Signatures', style: context.text.titleSmall),
                  const SizedBox(height: Space.x1),
                  Text(
                    _stamps.isEmpty
                        ? 'Nothing placed yet. Open the page view to add a '
                              'signature or the date.'
                        : '${_stamps.length} item'
                              '${_stamps.length == 1 ? '' : 's'} on page'
                              '${pages.length == 1 ? '' : 's'} '
                              '${pages.join(', ')}',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.x3),
                  FilledButton.tonalIcon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_document),
                    label: Text(
                      _stamps.isEmpty ? 'Place signature' : 'Edit placement',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (input != null) OutputNameField(controller: _name),
      ],
    );
  }

  void _run() {
    final input = _inputs.first;
    final stamps = [for (final s in _stamps) s.toPdfStamp()];
    final name = _name.text.trim().isEmpty
        ? '${input.name} (signed)'
        : _name.text.trim();
    final stamper = ref.read(pdfStamperProvider);
    final inspect = ref.read(inspectInputProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final pre = await inspect(
        input.path,
        accepts: const {DocumentFormat.pdf},
        nameHint: input.fileLabel,
      );
      if (pre case Err(:final failure)) {
        return Err(failure.withDetail(input.fileLabel));
      }
      report(0.2);
      final stamped = await stamper.stamp(input.path, stamps);
      report(0.95);
      return stamped.map((out) {
        _method = out.method;
        return [
          OutputFile(
            bytes: out.bytes,
            format: DocumentFormat.pdf,
            suggestedName: name,
            expectedPages: out.pageCount,
          ),
        ];
      });
    }, label: 'Signing PDF…');
  }
}

class _MethodNote extends StatelessWidget {
  const _MethodNote({required this.method});

  final StampMethod? method;

  @override
  Widget build(BuildContext context) {
    final (text, warn) = switch (method) {
      StampMethod.rasterized => (
        "This PDF couldn't be edited directly, so the signed pages were "
            'saved as images. Their text is no longer selectable.',
        true,
      ),
      StampMethod.rebuilt => (
        'Signed. This PDF had to be re-saved first, so bookmarks or form '
            'fields may be missing. Text stays selectable.',
        true,
      ),
      _ => ('Signed. Your pages and text are unchanged.', false),
    };
    return Text(
      text,
      textAlign: TextAlign.center,
      style: context.text.bodyMedium?.copyWith(
        color: warn ? context.ds.warning : context.ds.textSecondary,
      ),
    );
  }
}

/// Full-screen page view for placing, moving and resizing stamps. Pops with
/// the placed stamps (also on back, so nothing is lost).
class StampEditorScreen extends ConsumerStatefulWidget {
  const StampEditorScreen({
    required this.path,
    super.key,
    this.initialStamps = const [],
    this.clock = DateTime.now,
  });

  final String path;
  final List<PlacedStamp> initialStamps;
  final DateTime Function() clock;

  @override
  ConsumerState<StampEditorScreen> createState() => _StampEditorScreenState();
}

class _StampEditorScreenState extends ConsumerState<StampEditorScreen> {
  late var _stamps = [...widget.initialStamps];
  late var _nextId =
      widget.initialStamps.fold(0, (m, s) => s.id > m ? s.id : m) + 1;
  var _page = 0;
  int? _selected;

  void _update(int id, StampRect rect) => setState(() {
    _stamps = [
      for (final s in _stamps)
        if (s.id == id) s.withRect(rect) else s,
    ];
  });

  Future<void> _addSignature(PdfPageDimensions page) async {
    final image = await showSignaturePicker(context);
    if (image == null || !mounted) return;
    setState(() {
      final id = _nextId++;
      _stamps = [
        ..._stamps,
        PlacedStamp(
          id: id,
          pageIndex: _page,
          rect: initialSignatureRect(page, image.aspectRatio),
          image: image,
        ),
      ];
      _selected = id;
    });
  }

  void _addDate(PdfPageDimensions page) {
    final text = formatStampDate(widget.clock());
    final fontSize = (page.width / 50).clamp(8.0, 24.0);
    final probe = textStampRect(0, 0, text, fontSize);
    setState(() {
      final id = _nextId++;
      _stamps = [
        ..._stamps,
        PlacedStamp(
          id: id,
          pageIndex: _page,
          rect: clampToPage(
            textStampRect(
              (page.width - probe.width) / 2,
              page.height * 0.72 - probe.height * 1.5,
              text,
              fontSize,
            ),
            page,
          ),
          text: text,
        ),
      ];
      _selected = id;
    });
  }

  void _delete(int id) => setState(() {
    _stamps = [..._stamps]..removeWhere((s) => s.id == id);
    if (_selected == id) _selected = null;
  });

  @override
  Widget build(BuildContext context) {
    final dims = ref.watch(pdfPageDimensionsProvider(widget.path));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _stamps);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Place signature'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _stamps),
              child: const Text('Done'),
            ),
          ],
        ),
        body: switch (dims) {
          AsyncData(:final value) when value.isNotEmpty => _body(value),
          AsyncData() => const FailureView(
            AppFailure(FailureCode.corruptFile, detail: 'No pages'),
          ),
          AsyncError(:final error) => FailureView(
            error is AppFailure
                ? error
                : const AppFailure(
                    FailureCode.unknown,
                    heading: "This PDF couldn't be opened for signing",
                    message:
                        'The file is unchanged. Try again, or choose another '
                        'copy of the PDF.',
                    action: FailureAction.retry,
                  ),
            onRetry: () =>
                ref.invalidate(pdfPageDimensionsProvider(widget.path)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _body(List<PdfPageDimensions> pages) {
    final pageIndex = _page.clamp(0, pages.length - 1);
    final page = pages[pageIndex];
    final onPage = _stamps.where((s) => s.pageIndex == pageIndex).toList();
    final preview = ref.watch(pdfPagePreviewProvider((widget.path, pageIndex)));
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selected = null),
            child: ColoredBox(
              color: context.colors.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: page.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final viewport = PageViewport(
                          page: page,
                          viewWidth: constraints.maxWidth,
                        );
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 6,
                                      color: Colors.black26,
                                    ),
                                  ],
                                ),
                                child: switch (preview) {
                                  AsyncData(:final value) => Image.memory(
                                    value,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                  AsyncError() => const Center(
                                    child: Text("This page can't be shown"),
                                  ),
                                  _ => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                },
                              ),
                            ),
                            for (final s in onPage)
                              _StampView(
                                key: ValueKey('stamp-${s.id}'),
                                stamp: s,
                                viewport: viewport,
                                selected: s.id == _selected,
                                onSelect: () =>
                                    setState(() => _selected = s.id),
                                onChanged: (r) => _update(s.id, r),
                                onDelete: () => _delete(s.id),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x2,
              Space.gutter,
              Space.x2,
            ),
            child: Column(
              children: [
                if (pages.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: pageIndex > 0
                            ? () => setState(() {
                                _page = pageIndex - 1;
                                _selected = null;
                              })
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        'Page ${pageIndex + 1} of ${pages.length}',
                        style: context.text.titleSmall,
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: pageIndex < pages.length - 1
                            ? () => setState(() {
                                _page = pageIndex + 1;
                                _selected = null;
                              })
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                Text(
                  'Drag to move. Pinch or drag the corner to resize.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _addSignature(page),
                        icon: const Icon(Icons.draw_rounded),
                        label: const Text('Add signature'),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addDate(page),
                        icon: const Icon(Icons.event_rounded),
                        label: const Text('Add date'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StampView extends StatefulWidget {
  const _StampView({
    required this.stamp,
    required this.viewport,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final PlacedStamp stamp;
  final PageViewport viewport;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<StampRect> onChanged;
  final VoidCallback onDelete;

  @override
  State<_StampView> createState() => _StampViewState();
}

class _StampViewState extends State<_StampView> {
  StampRect? _start;
  Offset _focal = Offset.zero;

  PdfPageDimensions get _page => widget.viewport.page;

  @override
  Widget build(BuildContext context) {
    final s = widget.stamp;
    final rect = widget.viewport.toView(s.rect);
    final border = widget.selected
        ? Border.all(color: context.colors.primary, width: 1.5)
        : Border.all(color: Colors.black26, width: 0.5);
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              label: s.image != null
                  ? 'Signature on page ${s.pageIndex + 1}'
                  : 'Date ${s.text} on page ${s.pageIndex + 1}',
              selected: widget.selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onSelect,
                onScaleStart: (d) {
                  widget.onSelect();
                  _start = s.rect;
                  _focal = d.focalPoint;
                },
                onScaleUpdate: (d) {
                  final start = _start;
                  if (start == null) return;
                  var next = moveStamp(
                    start,
                    widget.viewport.deltaToPoints(d.focalPoint - _focal),
                    _page,
                  );
                  if (d.pointerCount > 1 && d.scale != 1) {
                    next = scaleStamp(next, d.scale, _page);
                  }
                  widget.onChanged(next);
                },
                onScaleEnd: (_) => _start = null,
                child: DecoratedBox(
                  decoration: BoxDecoration(border: border),
                  child: s.image != null
                      ? Image.memory(
                          s.image!.png,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        )
                      : FittedBox(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            s.text!,
                            style: const TextStyle(
                              color: Colors.black,
                              fontFamily: 'Helvetica',
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (widget.selected) ...[
            Positioned(
              top: -18,
              right: -18,
              child: _RoundButton(
                tooltip: 'Remove',
                icon: Icons.close_rounded,
                onPressed: widget.onDelete,
              ),
            ),
            Positioned(
              bottom: -14,
              right: -14,
              child: GestureDetector(
                key: const ValueKey('resize-handle'),
                onPanUpdate: (d) => widget.onChanged(
                  resizeStamp(
                    s.rect,
                    s.rect.width + widget.viewport.deltaToPoints(d.delta).dx,
                    _page,
                  ),
                ),
                child: Semantics(
                  label: 'Resize',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.errorContainer,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, color: context.colors.onErrorContainer),
    ),
  );
}
