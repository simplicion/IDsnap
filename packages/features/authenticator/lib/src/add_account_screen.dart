import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/src/secure_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manual entry: account name, issuer, Base32 key, and (advanced) type,
/// algorithm, digits and period/counter.
class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  static const nameRequired = 'Enter an account name.';
  static const periodInvalid = 'Enter a period between 1 and 3600 seconds.';
  static const counterInvalid = 'Enter a counter of 0 or more.';

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _secret = TextEditingController();
  final _period = TextEditingController(text: '30');
  final _counter = TextEditingController(text: '0');
  OtpType _type = OtpType.totp;
  OtpAlgorithm _algorithm = OtpAlgorithm.sha1;
  int _digits = 6;
  bool _saving = false;
  bool _obscureSecret = true;
  AppFailure? _failure;

  @override
  void dispose() {
    for (final c in [_name, _issuer, _secret, _period, _counter]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateSecret(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter the secret key.';
    return ref
        .read(otpCodecProvider)
        .normalizeSecret(v)
        .fold((_) => null, (f) => f.detail ?? f.title);
  }

  String? _validatePeriod(String? v) {
    if (_type != OtpType.totp) return null;
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 1 || n > 3600
        ? AddAccountScreen.periodInvalid
        : null;
  }

  String? _validateCounter(String? v) {
    if (_type != OtpType.hotp) return null;
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 0 ? AddAccountScreen.counterInvalid : null;
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final issuer = _issuer.text.trim();
    final result = await ref
        .read(authenticatorRepositoryProvider)
        .add(
          NewOtpAccount(
            label: _name.text.trim(),
            issuer: issuer.isEmpty ? null : issuer,
            secret: _secret.text,
            type: _type,
            algorithm: _algorithm,
            digits: _digits,
            period: _type == OtpType.totp ? int.parse(_period.text.trim()) : 30,
            counter: _type == OtpType.hotp
                ? int.parse(_counter.text.trim())
                : 0,
          ),
        );
    if (!mounted) return;
    result.fold(
      (account) {
        showAppSnack(context, 'Added ${account.title}');
        Navigator.of(context).pop();
      },
      (f) => setState(() {
        _saving = false;
        _failure = f;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return SecureScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Enter key manually')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'you@example.com',
                ),
                textInputAction: TextInputAction.next,
                validator: (v) => (v?.trim().isEmpty ?? true)
                    ? AddAccountScreen.nameRequired
                    : null,
              ),
              const SizedBox(height: Space.x3),
              TextFormField(
                controller: _issuer,
                decoration: const InputDecoration(
                  labelText: 'Issuer (optional)',
                  hintText: 'GitHub, Google, your bank…',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.x3),
              TextFormField(
                controller: _secret,
                obscureText: _obscureSecret,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'Secret key',
                  hintText: 'ABCD EFGH IJKL MNOP',
                  helperText: 'Letters A–Z and digits 2–7. Spaces are fine.',
                  suffixIcon: IconButton(
                    tooltip: _obscureSecret ? 'Show key' : 'Hide key',
                    onPressed: () =>
                        setState(() => _obscureSecret = !_obscureSecret),
                    icon: Icon(
                      _obscureSecret
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
                validator: _validateSecret,
              ),
              const SizedBox(height: Space.x2),
              ExpansionTile(
                title: const Text('Advanced'),
                subtitle: Text(
                  '${_type.label} · ${_algorithm.label} · $_digits digits',
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: Space.x3),
                children: [
                  _Labeled(
                    'Type',
                    SegmentedButton<OtpType>(
                      segments: [
                        for (final t in OtpType.values)
                          ButtonSegment(value: t, label: Text(t.label)),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) =>
                          setState(() => _type = s.single),
                    ),
                  ),
                  _Labeled(
                    'Algorithm',
                    SegmentedButton<OtpAlgorithm>(
                      segments: [
                        for (final a in OtpAlgorithm.values)
                          ButtonSegment(value: a, label: Text(a.label)),
                      ],
                      selected: {_algorithm},
                      onSelectionChanged: (s) =>
                          setState(() => _algorithm = s.single),
                    ),
                  ),
                  _Labeled(
                    'Digits',
                    SegmentedButton<int>(
                      segments: [
                        for (final d in NewOtpAccount.supportedDigits)
                          ButtonSegment(value: d, label: Text('$d')),
                      ],
                      selected: {_digits},
                      onSelectionChanged: (s) =>
                          setState(() => _digits = s.single),
                    ),
                  ),
                  if (_type == OtpType.totp)
                    TextFormField(
                      controller: _period,
                      decoration: const InputDecoration(
                        labelText: 'Period (seconds)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validatePeriod,
                    )
                  else
                    TextFormField(
                      controller: _counter,
                      decoration: const InputDecoration(labelText: 'Counter'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateCounter,
                    ),
                ],
              ),
              if (failure != null) ...[
                const SizedBox(height: Space.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${failure.title}. ${failure.detail ?? failure.recovery}',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Space.x5),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Add account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.labelLarge),
        const SizedBox(height: Space.x1),
        child,
      ],
    ),
  );
}
