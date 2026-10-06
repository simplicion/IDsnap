import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/src/auth_gate.dart';
import 'package:feature_authenticator/src/secure_scope.dart';
import 'package:feature_authenticator/src/services.dart';
import 'package:feature_authenticator/src/setup_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-account actions: rename, emergency recovery codes, delete.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(otpAccountsProvider);
    return SecureScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FailureView(
            e is AppFailure
                ? e
                : AppFailure(
                    FailureCode.unknown,
                    cause: e,
                    heading: "Your accounts couldn't be loaded",
                    message:
                        'They are still saved on this phone. Try again, or '
                        'restart IDSnap.',
                  ),
            onRetry: () => ref.invalidate(otpAccountsProvider),
          ),
          data: (list) {
            final account = list.where((a) => a.id == accountId).firstOrNull;
            if (account == null) {
              return const FailureView(
                AppFailure(
                  FailureCode.notFound,
                  message: 'This account was removed.',
                ),
              );
            }
            return _AccountBody(account: account);
          },
        ),
      ),
    );
  }
}

class _AccountBody extends ConsumerStatefulWidget {
  const _AccountBody({required this.account});

  final OtpAccount account;

  @override
  ConsumerState<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends ConsumerState<_AccountBody>
    with WidgetsBindingObserver {
  bool _recoveryOpen = false;
  bool _busy = false;
  List<RecoveryCode>? _codes;
  AppFailure? _recoveryFailure;

  OtpAccount get _account => widget.account;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _closeRecovery();
    }
  }

  void _closeRecovery() {
    if (!_recoveryOpen) return;
    setState(() {
      _recoveryOpen = false;
      _codes = null;
      _recoveryFailure = null;
    });
  }

  Future<void> _toggleRecovery() async {
    if (_recoveryOpen) return _closeRecovery();
    setState(() {
      _busy = true;
      _recoveryFailure = null;
    });
    // Always re-authenticate for recovery codes, even if codes are shown.
    final auth = await authenticateUser(
      ref,
      'Show recovery codes',
      acceptRecent: false,
    );
    if (!mounted) return;
    if (auth case Err(:final failure)) {
      setState(() {
        _busy = false;
        _recoveryFailure = failure;
      });
      return;
    }
    if (auth.valueOrNull != true) {
      setState(() => _busy = false);
      return;
    }
    final codes = await ref
        .read(authenticatorRepositoryProvider)
        .readRecoveryCodes(_account);
    if (!mounted) return;
    setState(() {
      _busy = false;
      codes.fold((c) {
        _recoveryOpen = true;
        _codes = c;
      }, (f) => _recoveryFailure = f);
    });
  }

  Future<void> _saveCodes(List<RecoveryCode> next) async {
    final r = await ref
        .read(authenticatorRepositoryProvider)
        .saveRecoveryCodes(_account, next);
    if (!mounted) return;
    r.fold(
      (_) => setState(() => _codes = next),
      (f) => showFailureSnack(context, f),
    );
  }

  Future<void> _addCodes(String text) async {
    final existing = {for (final c in _codes ?? <RecoveryCode>[]) c.code};
    final added = [
      for (final c in RecoveryCode.splitPasted(text))
        if (!existing.contains(c)) RecoveryCode(c),
    ];
    if (added.isEmpty) return;
    await _saveCodes([...?_codes, ...added]);
    if (mounted) {
      showAppSnack(
        context,
        added.length == 1 ? 'Code added' : '${added.length} codes added',
      );
    }
  }

  Future<void> _addOne() async {
    final text = await promptText(
      context,
      title: 'Add recovery code',
      confirmLabel: 'Add',
      hint: 'e.g. 1234-5678',
    );
    if (text != null && text.isNotEmpty) await _addCodes(text);
  }

  Future<void> _paste() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteDialog(),
    );
    if (text != null) await _addCodes(text);
  }

  Future<void> _copy(String code) async {
    await ref.read(secureClipboardProvider).copy(code);
    if (!mounted) return;
    showAppSnack(
      context,
      'Recovery code copied. The clipboard clears in '
      '${SecureClipboard.defaultClearAfter.inSeconds} seconds.',
    );
  }

  Future<void> _rename() async {
    final result = await showDialog<({String label, String issuer})>(
      context: context,
      builder: (context) => _RenameDialog(account: _account),
    );
    if (result == null) return;
    final r = await ref
        .read(authenticatorRepositoryProvider)
        .rename(_account.id, label: result.label, issuer: result.issuer);
    if (!mounted) return;
    if (r case Err(:final failure)) showFailureSnack(context, failure);
  }

  /// The account's `otpauth://` QR, always behind a fresh unlock.
  Future<void> _showSetupQr() async {
    final auth = await authenticateUser(
      ref,
      'Show the setup QR code',
      acceptRecent: false,
    );
    if (!mounted) return;
    if (auth case Err(:final failure)) {
      showFailureSnack(context, failure);
      return;
    }
    if (auth.valueOrNull != true) return;
    final secret = await ref
        .read(authenticatorRepositoryProvider)
        .readSecret(_account);
    if (!mounted) return;
    switch (secret) {
      case Ok(:final value):
        await showDialog<void>(
          context: context,
          builder: (_) => SetupQrDialog(
            title: _account.title,
            uri: otpAuthUri(_account, value),
          ),
        );
      case Err(:final failure):
        showFailureSnack(context, failure);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Remove ${_account.title}?',
      message:
          'Its secret key and recovery codes are erased from this phone. '
          'Turn off two-step verification on the website first, or you may '
          'be locked out.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref
        .read(authenticatorRepositoryProvider)
        .remove(_account.id);
    if (!mounted) return;
    r.fold((_) {
      showAppSnack(context, '${_account.title} removed');
      Navigator.of(context).pop();
    }, (f) => showFailureSnack(context, f));
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final details = [
      a.type.label,
      a.algorithm.label,
      '${a.digits} digits',
      if (a.type == OtpType.totp) '${a.period} s' else 'counter ${a.counter}',
    ].join(' · ');
    final noLock = ref.watch(authCapabilityProvider).value?.available == false;
    final codes = _codes;
    final failure = _recoveryFailure;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      children: [
        ListTile(
          leading: const IconBadge(Icons.shield_rounded),
          title: Text(a.title, style: context.text.titleMedium),
          subtitle: Text(
            [if (a.subtitle != null) a.subtitle!, details].join('\n'),
          ),
          isThreeLine: a.subtitle != null,
        ),
        ListTile(
          leading: const Icon(Icons.edit_rounded),
          title: const Text('Edit name and issuer'),
          onTap: _rename,
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_2_rounded),
          title: const Text('Show setup QR'),
          subtitle: const Text(
            'Move this account to another phone or authenticator app',
          ),
          onTap: _showSetupQr,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.password_rounded),
          title: const Text('Emergency recovery codes'),
          subtitle: const Text(
            'Backup codes from the website. Kept in secure storage on this '
            'phone.',
          ),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _recoveryOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
          onTap: _busy ? null : _toggleRecovery,
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(
              failure.detail ?? '${failure.title}. ${failure.recovery}',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        if (_recoveryOpen && codes != null) ...[
          if (noLock)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Text(
                'This phone has no screen lock, so recovery codes are shown '
                'without unlocking.',
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
          if (codes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                'No recovery codes saved. Add the codes the website gave you '
                'so you can sign in if you lose this phone’s codes.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
          for (var i = 0; i < codes.length; i++)
            _RecoveryRow(
              code: codes[i],
              onUsed: (used) => _saveCodes([
                for (final (j, c) in codes.indexed)
                  if (j == i) c.copyWith(used: used) else c,
              ]),
              onCopy: () => _copy(codes[i].code),
              onDelete: () => _saveCodes([...codes]..removeAt(i)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Wrap(
              spacing: Space.x2,
              children: [
                OutlinedButton.icon(
                  onPressed: _addOne,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add code'),
                ),
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste several'),
                ),
              ],
            ),
          ),
        ],
        const Divider(height: Space.x8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
            ),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remove account'),
          ),
        ),
      ],
    );
  }
}

class _RecoveryRow extends StatelessWidget {
  const _RecoveryRow({
    required this.code,
    required this.onUsed,
    required this.onCopy,
    required this.onDelete,
  });

  final RecoveryCode code;
  final ValueChanged<bool> onUsed;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Checkbox(
      value: code.used,
      semanticLabel: 'Used',
      onChanged: (v) => onUsed(v ?? false),
    ),
    title: Text(
      code.code,
      style: context.text.bodyLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 1.2,
        decoration: code.used ? TextDecoration.lineThrough : null,
        color: code.used ? context.ds.textSecondary : null,
      ),
    ),
    subtitle: code.used ? const Text('Used') : null,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Copy code',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
        ),
        IconButton(
          tooltip: 'Delete code',
          onPressed: onDelete,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paste recovery codes'),
    content: TextField(
      controller: _text,
      autofocus: true,
      minLines: 4,
      maxLines: 10,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        hintText: 'One code per line',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('Add codes'),
      ),
    ],
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.account});

  final OtpAccount account;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _label = TextEditingController(text: widget.account.label);
  late final _issuer = TextEditingController(text: widget.account.issuer);
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _issuer.dispose();
    super.dispose();
  }

  void _submit() {
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Enter an account name.');
      return;
    }
    Navigator.pop(context, (
      label: _label.text.trim(),
      issuer: _issuer.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit account'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _issuer,
          decoration: const InputDecoration(labelText: 'Issuer'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.x3),
        TextField(
          controller: _label,
          decoration: InputDecoration(
            labelText: 'Account name',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
