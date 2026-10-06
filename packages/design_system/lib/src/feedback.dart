import 'dart:async';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/src/support.dart';
import 'package:flutter/material.dart';

/// Shows a floating snackbar, optionally with an undo-style action.
void showAppSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

/// Shows "`title`. `recovery`". Unexpected failures also get a "Support"
/// action that opens an email draft (code and app version only).
void showFailureSnack(BuildContext context, AppFailure failure) {
  final support =
      failure.nextAction == FailureAction.contactSupport ||
      (failure.code == FailureCode.unknown && SupportContact.available);
  showAppSnack(
    context,
    '${failure.title}. ${failure.recovery}',
    actionLabel: support ? 'Support' : null,
    onAction: support
        ? () => unawaited(SupportContact.contact(context, failure: failure))
        : null,
  );
}

/// Confirmation for destructive or overwrite actions.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Single text field dialog (rename, new folder).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? hint,
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Human-readable byte size: 1.4 MB, 820 KB.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} ${units[i]}';
}

/// "Just now", "5 min ago", "Yesterday", "12 Mar 2026".
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
