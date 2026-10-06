import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/protect/unlock_inputs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Remove PDF password": the user knows the password and wants a copy
/// that opens without it. The result is saved to the library like any tool
/// output (validated, then committed).
class RemovePdfPasswordScreen extends ConsumerStatefulWidget {
  const RemovePdfPasswordScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<RemovePdfPasswordScreen> createState() =>
      _RemovePdfPasswordScreenState();
}

class _RemovePdfPasswordScreenState
    extends ConsumerState<RemovePdfPasswordScreen>
    with PreselectDocument {
  static const _job = 'remove-pdf-password';
  var _inputs = <ToolInput>[];
  final _password = TextEditingController();
  var _obscure = true;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  bool get unlockProtectedPdfs => false;
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _run() {
    final input = _inputs.single;
    final password = _password.text;
    final protector = ref.read(pdfProtectorProvider);
    final files = ref.read(fileStoreProvider);
    FocusScope.of(context).unfocus();
    ref.read(jobProvider(_job).notifier).start((report) async {
      final path = await tempOutputPath(files, 'unlocked.pdf');
      final r = await protector.removePdfPassword(
        input.path,
        password,
        outputPath: path,
      );
      switch (r) {
        case Err(:final failure):
          return Err(failure.withDetail(input.fileLabel));
        case Ok(:final value):
          final bytes = await files.read(value.path);
          await files.delete(value.path);
          return Ok([
            OutputFile(
              bytes: bytes,
              format: DocumentFormat.pdf,
              suggestedName: '${input.name} (no password)',
              expectedPages: value.pageCount,
            ),
          ]);
      }
    }, label: 'Removing the password…');
  }

  @override
  Widget build(BuildContext context) {
    final ready = _inputs.isNotEmpty && _password.text.isNotEmpty;
    return ToolScaffold(
      jobKey: _job,
      title: 'Remove PDF password',
      description:
          'Save a copy of a protected PDF that opens without a password. '
          'You need the current password. The original is not changed.',
      primaryLabel: _inputs.isEmpty
          ? 'Choose a PDF'
          : _password.text.isEmpty
          ? 'Enter the password'
          : 'Remove password',
      primaryIcon: Icons.lock_open_rounded,
      onPrimary: ready ? _run : null,
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: (v) => setState(() => _inputs = v),
          unlockPdfs: false,
          title: 'Protected PDF',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Current password', style: context.text.titleSmall),
            const SizedBox(height: Space.x2),
            TextField(
              key: const ValueKey('current-password'),
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => ready ? _run() : null,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.key_rounded),
                helperText:
                    'The open password, or the permissions password to '
                    'lift printing/copying limits. It is not saved.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
        const FidelityNote(
          label: 'Only for files you may unlock',
          explanation:
              'The copy opens for anyone who has it. Keep it in your ID '
              'Vault or share it only with people you trust.',
        ),
      ],
    );
  }
}
