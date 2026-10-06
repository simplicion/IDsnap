import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/protect/password_form.dart';
import 'package:feature_tools/src/protect/unlock_inputs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the protected output is.
enum ProtectOutput {
  pdf('Protected PDF'),
  zip('Protected ZIP');

  const ProtectOutput(this.label);
  final String label;
}

/// Instructions the user can pass on to the recipient of a protected ZIP.
const zipRecipientHelp =
    'It is an AES-256 encrypted ZIP. It opens with 7-Zip, WinRAR or WinZip '
    '(Windows), Keka or The Unarchiver (Mac: the built-in Archive Utility '
    "can't open AES ZIPs) and file managers that support encrypted ZIPs on "
    'Android and iPhone.';

const pdfRecipientHelp =
    'It is a password-protected PDF (AES-256). It opens in Adobe Acrobat '
    'Reader, Chrome, Edge, and the PDF viewers on Android, iPhone and Mac '
    'after entering the password.';

/// "Protect file": AES-256 PDF for PDFs, AES-256 ZIP for anything (or
/// several files in one ZIP). Nothing is stored unless the user saves the
/// output; the password is never stored.
class ProtectFileScreen extends ConsumerStatefulWidget {
  const ProtectFileScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<ProtectFileScreen> createState() => _ProtectFileScreenState();
}

sealed class _Phase {
  const _Phase();
}

final class _Form extends _Phase {
  const _Form();
}

final class _Running extends _Phase {
  const _Running(this.label, [this.progress]);
  final String label;
  final double? progress;
}

final class _Failed extends _Phase {
  const _Failed(this.failure);
  final AppFailure failure;
}

final class _Done extends _Phase {
  const _Done(this.outputs);
  final List<ProtectedOutput> outputs;
}

/// One protected file ready to share or save.
class ProtectedOutput {
  ProtectedOutput(this.file, this.name);

  final ProtectedFile file;

  /// Display name without extension.
  final String name;
  Document? saved;

  String get fileName => '$name.${file.format.extension}';
}

class _ProtectFileScreenState extends ConsumerState<ProtectFileScreen>
    with PreselectDocument {
  var _inputs = <ToolInput>[];
  ProtectOutput? _chosen;
  _Phase _phase = const _Form();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _owner = TextEditingController();
  final _zipName = TextEditingController();
  var _restrict = false;
  var _allowPrint = false;
  var _allowCopy = false;
  var _allowEdit = false;
  var _ownerObscure = true;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => DocumentFormat.values.toSet();
  // Protected PDFs are handled when protecting (current password prompt),
  // and go into a ZIP as they are.
  @override
  bool get unlockProtectedPdfs => false;
  @override
  void onPreselected(ToolInput input) => _setInputs([input]);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _owner.dispose();
    _zipName.dispose();
    super.dispose();
  }

  bool get _allPdf =>
      _inputs.isNotEmpty &&
      _inputs.every((i) => i.format == DocumentFormat.pdf);

  ProtectOutput get _output =>
      _allPdf ? (_chosen ?? ProtectOutput.pdf) : ProtectOutput.zip;

  void _setInputs(List<ToolInput> inputs) => setState(() {
    _inputs = inputs;
    if (inputs.length == 1) {
      _zipName.text = inputs.single.name;
    } else if (inputs.length > 1 &&
        (_zipName.text.isEmpty ||
            _inputs.any((i) => i.name == _zipName.text))) {
      _zipName.text = 'Protected files';
    }
  });

  String? _problem() {
    if (_inputs.isEmpty) return 'Choose at least one file.';
    final zip = _output == ProtectOutput.zip;
    final pw = PasswordSetup.problem(_password.text, _confirm.text, ascii: zip);
    if (pw != null) return pw;
    if (!zip && _restrict) {
      if (_owner.text.isEmpty) {
        return 'Enter a permissions password, or turn off restrictions.';
      }
      if (_owner.text == _password.text) {
        return 'The permissions password must differ from the open password.';
      }
    }
    return null;
  }

  Future<void> _run() async {
    final problem = _problem();
    if (problem != null) {
      showAppSnack(context, problem);
      return;
    }
    FocusScope.of(context).unfocus();
    final files = ref.read(fileStoreProvider);
    final password = _password.text;
    setState(() => _phase = const _Running('Encrypting…'));
    try {
      final outputs = <ProtectedOutput>[];
      if (_output == ProtectOutput.zip) {
        final name = _cleanName(_zipName.text, 'Protected files');
        final path = await tempOutputPath(files, '$name.zip');
        final r = await ref
            .read(protectedZipWriterProvider)
            .writeProtectedZip(
              [
                for (final i in _inputs)
                  ZipSource(path: i.path, fileName: i.fileLabel),
              ],
              password,
              outputPath: path,
              onProgress: (p) {
                if (mounted) {
                  setState(() => _phase = _Running('Encrypting…', p));
                }
              },
            );
        switch (r) {
          case Err(:final failure):
            _fail(failure);
            return;
          case Ok(:final value):
            outputs.add(ProtectedOutput(value, name));
        }
      } else {
        final protection = PdfProtection(
          openPassword: password,
          ownerPassword: _restrict ? _owner.text : null,
          allowPrinting: !_restrict || _allowPrint,
          allowCopying: !_restrict || _allowCopy,
          allowEditing: !_restrict || _allowEdit,
        );
        for (final (index, input) in _inputs.indexed) {
          if (!mounted) return;
          setState(
            () => _phase = _Running(
              _inputs.length == 1
                  ? 'Encrypting…'
                  : 'Encrypting ${index + 1} of ${_inputs.length}…',
              index / _inputs.length,
            ),
          );
          final name = '${input.name} (protected)';
          final path = await tempOutputPath(files, '${_fileSafe(name)}.pdf');
          final r = await _protectOne(input, protection, path);
          if (r == null) return; // cancelled or failed: phase already set
          outputs.add(ProtectedOutput(r, name));
        }
      }
      if (mounted) setState(() => _phase = _Done(outputs));
    } on Object catch (e, st) {
      _fail(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          message:
              'Protecting stopped unexpectedly and nothing was saved. Your '
              'original files are unchanged. Try again.',
        ),
      );
    }
  }

  /// Protects one PDF; asks for its current password when it already has
  /// one. Null when cancelled or failed (the phase is updated).
  Future<ProtectedFile?> _protectOne(
    ToolInput input,
    PdfProtection protection,
    String path,
  ) async {
    final protector = ref.read(pdfProtectorProvider);
    final first = await protector.protectPdf(
      input.path,
      protection,
      outputPath: path,
    );
    if (first case Ok(:final value)) return value;
    final failure = first.failureOrNull!;
    if (failure.code != FailureCode.passwordProtected) {
      _fail(failure.withDetail(input.fileLabel));
      return null;
    }
    if (!mounted) return null;
    ProtectedFile? done;
    final entered = await showPdfPasswordPrompt(
      context,
      fileName: input.fileLabel,
      title: 'Current password needed',
      action: 'Continue',
      verify: (current) async {
        final r = await protector.protectPdf(
          input.path,
          protection,
          outputPath: path,
          currentPassword: current,
        );
        return r.fold<String?>(
          (file) {
            done = file;
            return null;
          },
          (f) => f.code == FailureCode.wrongPassword
              ? "That password isn't right. ${f.recovery}"
              : '${f.title}. ${f.recovery}',
        );
      },
    );
    if (entered == null || done == null) {
      _fail(failure.withDetail(input.fileLabel));
      return null;
    }
    return done;
  }

  void _fail(AppFailure failure) {
    if (mounted) setState(() => _phase = _Failed(failure));
  }

  void _backToForm() => setState(() => _phase = const _Form());

  void _startOver() => setState(() {
    _phase = const _Form();
    _inputs = [];
    _password.clear();
    _confirm.clear();
    _owner.clear();
    _restrict = false;
  });

  static String _cleanName(String raw, String fallback) {
    final name = _fileSafe(raw.trim());
    return name.isEmpty ? fallback : name;
  }

  static String _fileSafe(String name) => name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final body = switch (phase) {
      _Form() => _form(context),
      _Running(:final label, :final progress) => ProgressPanel(
        label: label,
        progress: progress,
      ),
      _Failed(:final failure) => FailureView(
        failure,
        onRetry: _backToForm,
        actions: {
          FailureAction.pickDifferentFile: _backToForm,
          FailureAction.useFewerPages: _backToForm,
          FailureAction.none: _backToForm,
          FailureAction.freeStorage: () => context.go(Routes.settings),
        },
      ),
      _Done(:final outputs) => ProtectedResult(
        outputs: outputs,
        password: _password.text,
        onStartOver: _startOver,
      ),
    };
    return PopScope(
      canPop: phase is! _Running,
      child: Scaffold(
        appBar: AppBar(title: const Text('Protect file')),
        body: AnimatedSwitcher(duration: Motion.medium, child: body),
        bottomNavigationBar: phase is _Form
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.x2,
                  Space.gutter,
                  Space.x3,
                ),
                child: FilledButton.icon(
                  onPressed: _inputs.isEmpty ? null : _run,
                  icon: const Icon(Icons.lock_rounded),
                  label: Text(
                    _inputs.isEmpty
                        ? 'Choose files to protect'
                        : _output == ProtectOutput.zip
                        ? 'Create protected ZIP'
                        : _inputs.length == 1
                        ? 'Protect PDF'
                        : 'Protect ${_inputs.length} PDFs',
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _form(BuildContext context) {
    final zip = _output == ProtectOutput.zip;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        Space.x8,
      ),
      children: [
        Text(
          'Lock IDs, tax forms or any file with a password before sending '
          'it on WhatsApp or email. The recipient opens it with standard '
          'apps.',
          style: context.text.bodyLarge?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
        const SizedBox(height: Space.x3),
        const Align(alignment: Alignment.centerLeft, child: OfflineBadge()),
        const SizedBox(height: Space.x5),
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: _setInputs,
          multiple: true,
          anyFile: true,
          unlockPdfs: false,
          title: 'Files to protect',
        ),
        const SizedBox(height: Space.x5),
        if (_inputs.isNotEmpty) ...[
          if (_allPdf)
            ChoiceGroup<ProtectOutput>(
              label: 'Protect as',
              hint: zip
                  ? 'All files go into one encrypted ZIP.'
                  : _inputs.length > 1
                  ? 'Each PDF gets the same password.'
                  : 'Stays a PDF: it opens in any PDF viewer after '
                        'entering the password.',
              values: ProtectOutput.values,
              selected: _output,
              labelOf: (o) => o.label,
              onSelected: (o) => setState(() => _chosen = o),
            )
          else
            Text(
              'These files will go into one encrypted ZIP (AES-256).',
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          const SizedBox(height: Space.x5),
          if (zip) ...[
            Text('ZIP name', style: context.text.titleSmall),
            const SizedBox(height: Space.x2),
            TextField(
              controller: _zipName,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.folder_zip_outlined),
                suffixText: '.zip',
              ),
            ),
            const SizedBox(height: Space.x5),
          ],
        ],
        PasswordSetup(
          password: _password,
          confirm: _confirm,
          asciiOnly: zip,
          label: zip ? 'Password' : 'Open password',
          onChanged: () => setState(() {}),
        ),
        if (_inputs.isNotEmpty && !zip) ...[
          const SizedBox(height: Space.x4),
          _restrictions(context),
        ],
      ],
    );
  }

  Widget _restrictions(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: _restrict,
            onChanged: (v) => setState(() => _restrict = v),
            title: const Text('Restrict printing, copying and editing'),
            subtitle: const Text(
              'Optional. Needs a second "permissions" password. Most viewers '
              'respect these limits, but only the open password keeps the '
              'file private.',
            ),
          ),
          if (_restrict) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: TextField(
                key: const ValueKey('owner-field'),
                controller: _owner,
                obscureText: _ownerObscure,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Permissions password',
                  helperText: 'Different from the open password. Keep it.',
                  prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                  suffixIcon: IconButton(
                    tooltip: _ownerObscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _ownerObscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _ownerObscure = !_ownerObscure),
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: _allowPrint,
              onChanged: (v) => setState(() => _allowPrint = v ?? false),
              title: const Text('Allow printing'),
            ),
            CheckboxListTile(
              value: _allowCopy,
              onChanged: (v) => setState(() => _allowCopy = v ?? false),
              title: const Text('Allow copying text and images'),
            ),
            CheckboxListTile(
              value: _allowEdit,
              onChanged: (v) => setState(() => _allowEdit = v ?? false),
              title: const Text('Allow editing, comments and forms'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Success panel: share, save to the ID Vault or to the device.
class ProtectedResult extends ConsumerStatefulWidget {
  const ProtectedResult({
    required this.outputs,
    required this.password,
    required this.onStartOver,
    super.key,
  });

  final List<ProtectedOutput> outputs;
  final String password;
  final VoidCallback onStartOver;

  @override
  ConsumerState<ProtectedResult> createState() => _ProtectedResultState();
}

/// [saveFolderProvider] key of Protect file's "Save to ID Vault".
const protectFileSaveFlow = 'protect-file';

class _ProtectedResultState extends ConsumerState<ProtectedResult> {
  final _busy = <ProtectedOutput>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(saveFolderProvider(protectFileSaveFlow).notifier).start(null);
      }
    });
  }

  bool get _zip =>
      widget.outputs.any((o) => o.file.format == DocumentFormat.zip);

  Future<void> _share(List<ProtectedOutput> outputs) async {
    final r = await ref.read(shareServiceProvider).share([
      for (final o in outputs) o.file.path,
    ], subject: outputs.length == 1 ? outputs.single.name : null);
    if (r case Err(:final failure) when mounted) {
      showFailureSnack(context, failure);
    }
  }

  Future<void> _saveToVault(ProtectedOutput o) async {
    setState(() => _busy.add(o));
    try {
      final files = ref.read(fileStoreProvider);
      final bytes = await files.read(o.file.path);
      final folderId = await existingSaveFolder(
        () => ref.read(folderRepositoryProvider),
        ref.read(saveFolderProvider(protectFileSaveFlow)),
      );
      final r = await ref.read(commitOutputProvider)(
        OutputFile(
          bytes: bytes,
          format: o.file.format,
          suggestedName: o.name,
          expectedPages: o.file.pageCount,
          passwordProtected: o.file.format == DocumentFormat.pdf,
        ),
        folderId: folderId,
      );
      if (!mounted) return;
      r.fold((doc) {
        setState(() => o.saved = doc);
        final where = saveFolderLabel(
          ref.read(saveFolderTreeProvider).value,
          doc.folderId,
        );
        showAppSnack(context, 'Saved to $where');
      }, (f) => showFailureSnack(context, f));
    } on Object catch (e) {
      if (mounted) {
        showFailureSnack(
          context,
          AppFailure(
            FailureCode.unknown,
            cause: e,
            message:
                "The protected file couldn't be saved to ID Vault. Nothing "
                'was saved; try again or share it instead.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(o));
    }
  }

  Future<void> _saveToDevice(ProtectedOutput o) async {
    try {
      final bytes = await ref.read(fileStoreProvider).read(o.file.path);
      final r = await ref
          .read(shareServiceProvider)
          .saveToDevice(bytes, o.fileName);
      if (!mounted) return;
      r.fold((saved) {
        if (saved) showAppSnack(context, 'Saved ${o.fileName}');
      }, (f) => showFailureSnack(context, f));
    } on Object catch (e) {
      if (mounted) {
        showFailureSnack(context, AppFailure(FailureCode.notFound, cause: e));
      }
    }
  }

  Future<void> _copy(String text, String done) async {
    final r = await ref.read(shareServiceProvider).copyText(text);
    if (!mounted) return;
    r.fold(
      (_) => showAppSnack(context, done),
      (f) => showFailureSnack(context, f),
    );
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.outputs.length > 1;
    final help = _zip ? zipRecipientHelp : pdfRecipientHelp;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.x4),
        Center(
          child: IconBadge(
            Icons.lock_rounded,
            color: context.ds.success,
            size: 72,
          ),
        ),
        const SizedBox(height: Space.x4),
        Text(
          many ? '${widget.outputs.length} files protected' : 'File protected',
          style: context.text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.x1),
        Text(
          'Encrypted with AES-256 on this phone. Not saved anywhere yet.',
          style: context.text.bodyMedium?.copyWith(
            color: context.ds.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.x5),
        FilledButton.icon(
          onPressed: () => _share(widget.outputs),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(many ? 'Share all' : 'Share'),
        ),
        const SizedBox(height: Space.x4),
        const SaveFolderField(flow: protectFileSaveFlow),
        const SizedBox(height: Space.x3),
        for (final o in widget.outputs) _row(context, o),
        const SizedBox(height: Space.x2),
        const FidelityNote(
          label: 'Send the password separately',
          explanation: sendSeparatelyTip,
          limitations: [passwordNotKeptWarning],
        ),
        const SizedBox(height: Space.x3),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            OutlinedButton.icon(
              onPressed: () => _copy(widget.password, 'Password copied'),
              icon: const Icon(Icons.key_rounded),
              label: const Text('Copy password'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy(
                'I sent you a protected file. $help I will send you the '
                    'password separately.',
                'Instructions copied',
              ),
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Copy opening instructions'),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        Text(
          help,
          style: context.text.bodySmall?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
        const SizedBox(height: Space.x4),
        OutlinedButton.icon(
          onPressed: widget.onStartOver,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Protect more files'),
        ),
        const SizedBox(height: Space.x2),
        TextButton(
          onPressed: () => context.canPop() ? context.pop() : null,
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ProtectedOutput o) {
    final v = formatVisual(context, o.file.format);
    final pages = o.file.pageCount;
    final kind = o.file.format == DocumentFormat.zip
        ? 'Encrypted ZIP'
        : 'Protected PDF';
    final details = [
      kind,
      formatBytes(o.file.sizeBytes),
      if (pages != null) '$pages page${pages == 1 ? '' : 's'}',
    ].join(' · ');
    final saved = o.saved;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(v.icon, color: v.color),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.fileName,
                          style: context.text.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          details,
                          style: context.text.bodySmall?.copyWith(
                            color: context.ds.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                children: [
                  TextButton.icon(
                    onPressed: () => _share([o]),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share'),
                  ),
                  if (saved == null)
                    TextButton.icon(
                      onPressed: _busy.contains(o)
                          ? null
                          : () => _saveToVault(o),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Save to ID Vault'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => context.push(Routes.document(saved.id)),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Saved · Open'),
                    ),
                  TextButton.icon(
                    onPressed: () => _saveToDevice(o),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Save to device'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
