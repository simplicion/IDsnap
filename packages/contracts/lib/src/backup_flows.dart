import 'dart:async';

import 'package:docscan_contracts/src/providers.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Shared UI for the full backup and "Export accounts" (audit H-04/H-05):
// password choice, re-authentication, a cancellable progress dialog,
// delivery (save / send) and the import summary. Used by Settings › Your
// data and by the Authenticator.

/// Minimum length for a backup password.
const minBackupPasswordLength = 8;

/// Why [password] can't protect a backup, or null when it can. Only
/// printable ASCII: unzip apps disagree on other characters.
String? backupPasswordProblem(String password) {
  if (password.length < minBackupPasswordLength) {
    return 'Use at least $minBackupPasswordLength characters.';
  }
  for (final c in password.codeUnits) {
    if (c < 0x20 || c > 0x7E) {
      return 'Use only English letters, digits and standard symbols, so '
          'every unzip app can open the backup.';
    }
  }
  return null;
}

/// Asks the phone's biometrics or screen lock (whether or not App Lock is
/// on). A phone with no screen lock has nothing to ask.
Future<bool> reauthenticateForBackup(WidgetRef ref, String reason) async {
  final lock = ref.read(appLockProvider);
  if (!(await lock.capability()).available) return true;
  final r = await lock.authenticate(reason);
  return r.valueOrNull ?? false;
}

/// The user's choice in [askExportOptions].
typedef ExportChoice = ({String? password});

/// Explains what the export contains and asks for a password. With
/// [allowUnprotected] the user may switch protection off (default ON) after
/// a clear warning. Returns null when cancelled.
Future<ExportChoice?> askExportOptions(
  BuildContext context, {
  required String title,
  required List<String> included,
  List<String> notIncluded = const [],
  bool allowUnprotected = true,
}) => showDialog<ExportChoice>(
  context: context,
  builder: (_) => _ExportOptionsDialog(
    title: title,
    included: included,
    notIncluded: notIncluded,
    allowUnprotected: allowUnprotected,
  ),
);

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.title,
    required this.included,
    required this.notIncluded,
    required this.allowUnprotected,
  });

  final String title;
  final List<String> included;
  final List<String> notIncluded;
  final bool allowUnprotected;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _protect = true;
  var _understood = false;
  var _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_protect) {
      if (!_understood) {
        setState(() => _error = 'Tick the box to confirm.');
        return;
      }
      Navigator.pop<ExportChoice>(context, (password: null));
      return;
    }
    final problem = backupPasswordProblem(_password.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = "The passwords don't match.");
      return;
    }
    Navigator.pop<ExportChoice>(context, (password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Included', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          ...widget.included.map(bullet),
          if (widget.notIncluded.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Not included', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            ...widget.notIncluded.map(bullet),
          ],
          const SizedBox(height: 8),
          if (widget.allowUnprotected)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Protect this backup with a password'),
              subtitle: const Text('AES-256. Opens in 7-Zip, WinZip, Keka.'),
              value: _protect,
              onChanged: (v) => setState(() {
                _protect = v;
                _error = null;
              }),
            ),
          if (_protect) ...[
            TextField(
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText:
                    'At least $minBackupPasswordLength characters. Without '
                    "it the backup can't be opened — IDSnap can't recover it.",
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Text(
              'File and folder names stay readable in the ZIP; their '
              'contents need the password.',
              style: theme.textTheme.bodySmall,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Not protected: anyone who gets this file can open every '
                'document and note in it, and read your two-step '
                'verification secret keys. Only use this for a computer or '
                'drive that only you can access.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: const Text('I understand the backup is not encrypted'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Export')),
      ],
    );
  }
}

/// Asks for a backup's password on import; null when cancelled.
Future<String?> askImportPassword(BuildContext context, {bool retry = false}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(retry ? 'Wrong password' : 'Backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            retry
                ? "That password doesn't open this backup. Passwords are "
                      'case-sensitive.'
                : 'This backup is protected. Enter the password you chose '
                      'when you exported it.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Open'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Runs [job] behind a modal progress dialog with a Cancel button.
Future<Result<T>> runBackupJob<T>(
  BuildContext context, {
  required String title,
  required Future<Result<T>> Function(
    void Function(BackupProgress) onProgress,
    JobCancelToken cancel,
  )
  job,
}) async {
  final progress = ValueNotifier<BackupProgress?>(null);
  final cancel = JobCancelToken();
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<BackupProgress?>(
            valueListenable: progress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p?.fraction),
                const SizedBox(height: 12),
                Text(
                  p == null
                      ? 'Preparing…'
                      : [p.stage.label, ?p.item].join(' · '),
                ),
                const SizedBox(height: 4),
                Text(
                  'Keep IDSnap open until this finishes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: cancel.cancel, child: const Text('Cancel')),
          ],
        ),
      ),
    ),
  );
  try {
    return await job((p) => progress.value = p, cancel);
  } finally {
    navigator.pop();
    progress.dispose();
  }
}

/// Lets the user save or send a finished backup, then shreds the copy in
/// the app cache.
Future<void> deliverBackup(
  BuildContext context,
  WidgetRef ref,
  BackupResult backup,
) async {
  final files = ref.read(plainFileAccessProvider);
  var shared = false;
  try {
    while (context.mounted) {
      final action = await showModalBottomSheet<String>(
        context: context,
        isDismissible: false,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    backup.protected
                        ? 'Backup ready · password-protected'
                        : 'Backup ready · NOT encrypted',
                  ),
                  subtitle: Text(
                    '${backup.fileName} · '
                    '${(backup.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Save to this phone'),
                  subtitle: const Text('Files / Downloads'),
                  onTap: () => Navigator.pop(context, 'save'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Send…'),
                  subtitle: const Text(
                    'Quick Share to your new phone, Drive, a computer',
                  ),
                  onTap: () => Navigator.pop(context, 'send'),
                ),
                ListTile(
                  leading: const Icon(Icons.check),
                  title: const Text('Done'),
                  subtitle: const Text('The copy inside IDSnap is deleted'),
                  onTap: () => Navigator.pop(context, 'done'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!context.mounted || action == null || action == 'done') return;
      final Result<Object?> r;
      if (action == 'save') {
        r = await ref
            .read(fileSaverProvider)
            .saveFileToDevice(backup.path, backup.fileName);
      } else {
        shared = true;
        r = await ref.read(shareServiceProvider).share([
          backup.path,
        ], subject: backup.fileName);
      }
      if (!context.mounted) return;
      final failure = r.failureOrNull;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure == null
                ? (action == 'save' && r.valueOrNull == false
                      ? 'Not saved'
                      : 'Backup handed over')
                : '${failure.title}. ${failure.recovery}',
          ),
        ),
      );
    }
  } finally {
    // The receiving app may still be reading a shared file.
    await files.releaseTemp(
      backup.path,
      grace: shared ? const Duration(minutes: 2) : Duration.zero,
    );
  }
}

/// Picks a backup, asks for its password when needed, imports it and shows
/// what came back. Returns the summary, or null when nothing was imported.
Future<ImportSummary?> importBackupFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final picked = await ref.read(mediaPickerProvider).pickFiles({
    DocumentFormat.zip,
  });
  if (!context.mounted) return null;
  final file = picked.valueOrNull?.firstOrNull;
  if (file == null) {
    final f = picked.failureOrNull;
    if (f != null && f.code != FailureCode.captureCancelled) {
      _snack(context, '${f.title}. ${f.recovery}');
    }
    return null;
  }
  final archiver = ref.read(libraryArchiverProvider);
  final sections = ref.read(backupSectionsProvider);
  String? password;
  var retry = false;
  while (true) {
    if (!context.mounted) return null;
    final result = await runBackupJob<ImportSummary>(
      context,
      title: 'Importing backup',
      job: (onProgress, cancel) => archiver.importBackup(
        file.path,
        password: password,
        sections: sections,
        onProgress: onProgress,
        cancel: cancel,
      ),
    );
    if (!context.mounted) return null;
    switch (result) {
      case Ok(:final value):
        await showImportSummary(context, value);
        return value;
      case Err(:final failure)
          when failure.code == FailureCode.passwordProtected ||
              failure.code == FailureCode.wrongPassword:
        password = await askImportPassword(context, retry: retry);
        retry = true;
        if (password == null) return null;
      case Err(:final failure):
        _snack(context, '${failure.title}. ${failure.recovery}');
        return null;
    }
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// What an import brought back, including anything that needs attention.
Future<void> showImportSummary(BuildContext context, ImportSummary s) {
  String n(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
  const labels = {
    'authenticator': ('authenticator account', 'authenticator accounts'),
    'signatures': ('signature', 'signatures'),
    'qr-history': ('QR history entry', 'QR history entries'),
  };
  final lines = <String>[
    if (s.documents > 0) n(s.documents, 'document', 'documents'),
    if (s.folders > 0) n(s.folders, 'folder', 'folders'),
    if (s.notes > 0) n(s.notes, 'note', 'notes'),
    for (final MapEntry(:key, :value) in s.sections.entries)
      if (value > 0 && labels[key] != null)
        n(value, labels[key]!.$1, labels[key]!.$2)
      else if (value > 0 && key == 'settings')
        'Settings',
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.total == 0 ? 'Nothing new to import' : 'Backup imported'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.total == 0
                ? 'Everything in this backup is already here.'
                : 'Restored: ${lines.join(', ')}. Everything is encrypted '
                      'again on this phone.',
          ),
          if (s.pinLockedFolders > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${n(s.pinLockedFolders, 'folder', 'folders')} had a PIN. PINs '
              "don't travel between phones, so they are locked with this "
              "phone's screen lock now. Set a PIN again in the folder menu.",
            ),
          ],
          for (final MapEntry(:key, :value) in s.failedSections.entries) ...[
            const SizedBox(height: 8),
            Text(
              "$key couldn't be restored: ${value.title}. ${value.recovery}",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
