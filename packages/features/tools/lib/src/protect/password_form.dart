import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_tools/src/protect/password_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The warning shown wherever a password is set.
const passwordNotKeptWarning =
    "IDSnap doesn't keep this password. If you lose it, the file can't be "
    'opened.';

/// Advice shown next to the password and after protecting.
const sendSeparatelyTip =
    'Send the password another way than the file: for example, share the '
    'file by email and tell the password on a call or by SMS.';

/// Password + confirmation with show/hide, a generator, copy and a strength
/// meter. The parent owns the controllers and reads [isValid].
class PasswordSetup extends ConsumerStatefulWidget {
  const PasswordSetup({
    required this.password,
    required this.confirm,
    required this.onChanged,
    super.key,
    this.label = 'Password',
    this.asciiOnly = false,
  });

  final TextEditingController password;
  final TextEditingController confirm;
  final VoidCallback onChanged;
  final String label;

  /// ZIP passwords: only printable ASCII (see [zipPasswordProblem]).
  final bool asciiOnly;

  /// Why [password]/[confirm] can't be used yet, or null when they can.
  static String? problem(
    String password,
    String confirm, {
    bool ascii = false,
  }) {
    if (password.isEmpty) return 'Enter or generate a password.';
    final strength = estimatePasswordStrength(password).strength;
    if (!strength.acceptable) return 'Choose a stronger password.';
    if (ascii) {
      final zip = zipPasswordProblem(password);
      if (zip != null) return zip;
    }
    if (password.length > 127) return 'Use at most 127 characters.';
    if (confirm != password) return "The passwords don't match.";
    return null;
  }

  @override
  ConsumerState<PasswordSetup> createState() => _PasswordSetupState();
}

class _PasswordSetupState extends ConsumerState<PasswordSetup> {
  var _obscure = true;

  void _generate() {
    final pw = generatePassword();
    widget.password.text = pw;
    widget.confirm.text = pw;
    // A generated password is useless unseen: reveal it.
    setState(() => _obscure = false);
    widget.onChanged();
  }

  Future<void> _copy() async {
    final text = widget.password.text;
    if (text.isEmpty) return;
    try {
      await ref.read(shareServiceProvider).copyText(text);
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
    }
    if (mounted) showAppSnack(context, 'Password copied');
  }

  @override
  Widget build(BuildContext context) {
    final pw = widget.password.text;
    final estimate = estimatePasswordStrength(pw);
    final zipIssue = widget.asciiOnly ? zipPasswordProblem(pw) : null;
    final mismatch =
        widget.confirm.text.isNotEmpty && widget.confirm.text != pw;
    final meterColor = switch (estimate.strength) {
      PasswordStrength.tooWeak || PasswordStrength.weak => context.colors.error,
      PasswordStrength.fair => context.ds.warning,
      _ => context.ds.success,
    };
    final toggle = IconButton(
      tooltip: _obscure ? 'Show password' : 'Hide password',
      icon: Icon(
        _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: context.text.titleSmall),
        const SizedBox(height: Space.x2),
        TextField(
          key: const ValueKey('password-field'),
          controller: widget.password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: toggle,
            errorText: zipIssue,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.x2),
        if (pw.isNotEmpty) ...[
          Semantics(
            label: 'Password strength: ${estimate.strength.label}',
            child: ClipRRect(
              borderRadius: Radii.smAll,
              child: LinearProgressIndicator(
                value: estimate.strength.fill,
                minHeight: 6,
                color: meterColor,
                backgroundColor: context.colors.surfaceContainerHigh,
              ),
            ),
          ),
          const SizedBox(height: Space.x1),
          Text(
            [
              'Strength: ${estimate.strength.label}',
              if (estimate.hint != null) estimate.hint!,
            ].join(' · '),
            style: context.text.bodySmall?.copyWith(
              color: estimate.strength.acceptable
                  ? context.ds.textSecondary
                  : context.colors.error,
            ),
          ),
          const SizedBox(height: Space.x2),
        ],
        TextField(
          key: const ValueKey('confirm-field'),
          controller: widget.confirm,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_reset_rounded),
            errorText: mismatch ? "The passwords don't match." : null,
          ),
        ),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            OutlinedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Generate strong password'),
            ),
            TextButton.icon(
              onPressed: pw.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        const FidelityNote(
          label: 'Keep this password safe',
          explanation: passwordNotKeptWarning,
          limitations: [sendSeparatelyTip],
        ),
      ],
    );
  }
}
