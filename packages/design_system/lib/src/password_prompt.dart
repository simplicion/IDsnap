import 'package:docscan_design_system/src/tokens.dart';
import 'package:flutter/material.dart';

/// Asks for the password of a protected PDF and checks it with [verify]
/// (which returns an error message for a wrong password, or null when the
/// password worked). Returns the password, or null when cancelled.
///
/// [message] replaces the default explanation ("… Enter its password to use
/// it here. The password is not saved.").
Future<String?> showPdfPasswordPrompt(
  BuildContext context, {
  required String fileName,
  required Future<String?> Function(String password) verify,
  String title = 'Password needed',
  String action = 'Unlock',
  String? message,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PasswordPrompt(
    fileName: fileName,
    verify: verify,
    title: title,
    action: action,
    message: message,
  ),
);

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({
    required this.fileName,
    required this.verify,
    required this.title,
    required this.action,
    required this.message,
  });

  final String fileName;
  final Future<String?> Function(String password) verify;
  final String title;
  final String action;
  final String? message;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();
  var _obscure = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _controller.text;
    if (pw.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.verify(pw);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, pw);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.message ??
              '"${widget.fileName}" is protected. Enter its password to use '
                  'it here. The password is not saved.',
        ),
        const SizedBox(height: Space.x3),
        TextField(
          key: const ValueKey('pdf-password-prompt'),
          controller: _controller,
          autofocus: true,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_busy,
          keyboardType: TextInputType.visiblePassword,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: _error,
            errorMaxLines: 3,
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
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy || _controller.text.isEmpty ? null : _submit,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(widget.action),
      ),
    ],
  );
}
