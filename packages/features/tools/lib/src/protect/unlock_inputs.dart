import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A fresh path `<app tmp>/<id>/<fileName>` for an engine to write to.
/// Temp files are cleared by the file store; nothing here is in the library.
Future<String> tempOutputPath(FileStore files, String fileName) async {
  final probe = await files.writeTemp(Uint8List(0), 'tmp');
  await files.delete(probe);
  final sep = probe.contains(r'\') && !probe.contains('/') ? r'\' : '/';
  final dir = probe.substring(0, probe.lastIndexOf(sep));
  return '$dir$sep${newId()}$sep$fileName';
}

/// For every password-protected PDF in [inputs], asks for its password and
/// swaps in a decrypted temp copy, so any tool can work on it. Inputs whose
/// prompt is cancelled are dropped (with a note). Other inputs pass through.
/// Without a wired [PdfProtector] (tests, previews) inputs are unchanged.
Future<List<ToolInput>> unlockProtectedPdfs(
  BuildContext context,
  WidgetRef ref,
  List<ToolInput> inputs,
) async {
  if (!inputs.any((i) => i.format == DocumentFormat.pdf)) return inputs;
  final PdfProtector protector;
  try {
    protector = ref.read(pdfProtectorProvider);
  } on Object {
    return inputs;
  }
  final files = ref.read(fileStoreProvider);
  final out = <ToolInput>[];
  final skipped = <String>[];
  for (final input in inputs) {
    if (input.format != DocumentFormat.pdf) {
      out.add(input);
      continue;
    }
    final needs = await protector.needsPassword(input.path);
    if (needs.valueOrNull != true) {
      // Not protected, or unreadable: the tool reports that itself.
      out.add(input);
      continue;
    }
    if (!context.mounted) return inputs;
    ToolInput? unlocked;
    final password = await showPdfPasswordPrompt(
      context,
      fileName: input.fileLabel,
      verify: (pw) async {
        try {
          final path = await tempOutputPath(files, 'unlocked.pdf');
          final r = await protector.removePdfPassword(
            input.path,
            pw,
            outputPath: path,
          );
          final message = r.fold<String?>(
            (file) {
              unlocked = ToolInput(
                path: file.path,
                name: input.name,
                format: DocumentFormat.pdf,
                sizeBytes: file.sizeBytes,
                documentId: input.documentId,
              );
              return null;
            },
            (f) => f.code == FailureCode.wrongPassword
                ? "That password isn't right. ${f.recovery}"
                : '${f.title}. ${f.recovery}',
          );
          return message;
        } on Object {
          return "The file couldn't be unlocked. Try again.";
        }
      },
    );
    if (password != null && unlocked != null) {
      out.add(unlocked!);
    } else {
      skipped.add(input.fileLabel);
    }
  }
  if (skipped.isNotEmpty && context.mounted) {
    showAppSnack(
      context,
      skipped.length == 1
          ? '${skipped.single} was not added: it needs its password.'
          : '${skipped.length} files were not added: they need passwords.',
    );
  }
  return out;
}
