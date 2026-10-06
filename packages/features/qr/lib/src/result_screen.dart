import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/src/services.dart';
import 'package:feature_qr/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What a scanned code contains, with actions for its type. Nothing runs
/// automatically: every action is a button the user taps.
class CodeResultScreen extends ConsumerStatefulWidget {
  const CodeResultScreen({required this.code, super.key});

  final ScannedCode code;

  static const wifiJoinNote =
      'To join, open Wi-Fi settings on your phone, pick this network and '
      'paste the password. IDSnap never connects to networks itself.';
  static const paymentNote =
      'Shown for reference only. IDSnap never makes payments or opens '
      'payment apps. Check the details before paying in your own app.';
  static const idCardNote =
      'Personal data decoded on this phone. It is not kept in scan history '
      'unless you allow sensitive items.';
  static const otpNote =
      'This code sets up two-step verification. The secret key is never '
      'shown or copied; add it to the Authenticator instead.';

  @override
  ConsumerState<CodeResultScreen> createState() => _CodeResultScreenState();
}

class _CodeResultScreenState extends ConsumerState<CodeResultScreen> {
  late final CodeContent content = CodeParser.parseCode(widget.code);
  final _revealed = <int>{};
  bool _busy = false;

  QrActions get _actions => ref.read(qrActionsProvider);

  void _snack(String message) {
    if (mounted) showAppSnack(context, message);
  }

  void _failure(AppFailure f) {
    if (mounted) showFailureSnack(context, f);
  }

  Future<void> _copy(String text, {String what = 'Copied'}) async {
    final r = await _actions.copy(text);
    r.fold((_) => _snack(what), _failure);
  }

  Future<void> _shareText() async {
    final r = await _actions.shareText(content.toPlainText());
    if (r case Err(:final failure)) _failure(failure);
  }

  Future<void> _open(Uri uri, {required String failed}) async {
    final ok = await _actions.open(uri);
    if (!ok) _snack(failed);
  }

  Future<void> _shareFile(String text, String ext, String subject) async {
    final r = await _actions.shareFile(
      Uint8List.fromList(utf8.encode(text)),
      extension: ext,
      subject: subject,
    );
    if (r case Err(:final failure)) _failure(failure);
  }

  Future<void> _openLink(UrlContent url) async {
    if (url.safety.hasWarnings) {
      final go = await confirmAction(
        context,
        title: url.safety.isSuspicious
            ? 'This link looks suspicious'
            : 'Open this link?',
        message:
            '${url.safety.warnings.map((w) => '• ${w.title}').join('\n')}'
            '\n\n${url.url}\n\nIt opens in your browser, outside IDSnap.',
        confirmLabel: 'Open anyway',
        destructive: url.safety.isSuspicious,
      );
      if (!go) return;
    }
    await _open(Uri.parse(url.url), failed: 'No browser could open this link.');
  }

  Future<void> _saveToVault() async {
    if (content.isSensitive) {
      final ok = await confirmAction(
        context,
        title: 'Save sensitive details?',
        message:
            'This note will include ${_sensitiveWhat()}. It is stored only '
            'on this phone, in your ID Vault.',
        confirmLabel: 'Save',
      );
      if (!ok || !mounted) return;
    }
    if (!await pickQrSaveFolder(context, ref) || !mounted) return;
    setState(() => _busy = true);
    final r = await _actions.saveToVault(
      Uint8List.fromList(utf8.encode(_noteText())),
      format: DocumentFormat.txt,
      name: '${content.title} – ${content.summary}',
      folderId: ref.read(saveFolderProvider(qrSaveFlow)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (doc) => _snack(
        'Saved to '
        '${saveFolderLabel(ref.read(saveFolderTreeProvider).value, doc.folderId)}',
      ),
      _failure,
    );
  }

  String _sensitiveWhat() => switch (content) {
    WifiContent() => 'the Wi-Fi password',
    PaymentContent() => 'the payment details',
    IdCardContent() => 'personal identity data',
    _ => 'sensitive details',
  };

  String _noteText() {
    final b = StringBuffer(content.toPlainText());
    if (content is! TextContent) {
      b
        ..write('\n\nScanned ${widget.code.symbology.label} content:\n')
        ..write(widget.code.raw);
    }
    return b.toString();
  }

  Future<void> _addToAuthenticator() async {
    final parsed = ref.read(otpCodecProvider).parseUri(widget.code.raw);
    switch (parsed) {
      case Err(:final failure):
        _failure(failure);
        return;
      case Ok(:final value):
        final ok = await confirmAction(
          context,
          title: 'Add to Authenticator?',
          message: [
            if (value.issuer != null) value.issuer!,
            value.label,
          ].join(' · '),
          confirmLabel: 'Add',
        );
        if (!ok || !mounted) return;
        setState(() => _busy = true);
        final added = await ref
            .read(authenticatorRepositoryProvider)
            .add(value);
        if (!mounted) return;
        setState(() => _busy = false);
        switch (added) {
          case Ok(value: final account):
            _snack('Added ${account.title}');
            GoRouter.maybeOf(context)?.go(Routes.authenticator);
          case Err(:final failure):
            _failure(failure);
        }
    }
  }

  List<Widget> _primaryActions() {
    Widget filled(IconData icon, String label, VoidCallback onPressed) =>
        FilledButton.icon(
          onPressed: _busy ? null : onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
    Widget outlined(IconData icon, String label, VoidCallback onPressed) =>
        OutlinedButton.icon(
          onPressed: _busy ? null : onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
    final c = content;
    return switch (c) {
      UrlContent() => [
        if (c.canOpen)
          filled(
            Icons.open_in_browser_rounded,
            'Open in browser',
            () => unawaited(_openLink(c)),
          ),
        outlined(
          Icons.copy_rounded,
          'Copy link',
          () => unawaited(_copy(c.url, what: 'Link copied')),
        ),
      ],
      WifiContent() => [
        if (c.password != null)
          filled(
            Icons.key_rounded,
            'Copy password',
            () => unawaited(_copy(c.password!, what: 'Password copied')),
          ),
        outlined(
          Icons.wifi_rounded,
          'Copy network name',
          () => unawaited(_copy(c.ssid, what: 'Network name copied')),
        ),
      ],
      ContactContent() => [
        filled(
          Icons.person_add_alt_1_rounded,
          'Add to contacts',
          () => unawaited(
            _shareFile(c.card.toVCard(), 'vcf', c.card.displayName),
          ),
        ),
      ],
      EmailContent() => [
        filled(
          Icons.edit_rounded,
          'Write email',
          () => unawaited(
            _open(Uri.parse(c.mailtoUri), failed: 'No email app found.'),
          ),
        ),
      ],
      PhoneContent() => [
        filled(
          Icons.call_rounded,
          'Call',
          () => unawaited(
            _open(Uri.parse(c.telUri), failed: 'No phone app found.'),
          ),
        ),
        outlined(
          Icons.copy_rounded,
          'Copy number',
          () => unawaited(_copy(c.number, what: 'Number copied')),
        ),
      ],
      SmsContent() => [
        filled(
          Icons.send_rounded,
          'Send message',
          () => unawaited(
            _open(Uri.parse(c.smsUri), failed: 'No messaging app found.'),
          ),
        ),
      ],
      GeoContent() => [
        filled(
          Icons.map_rounded,
          'Open in maps',
          () => unawaited(
            _open(
              Uri.parse(
                ref.read(useAppleMapsProvider) ? c.appleMapsUri : c.geoUri,
              ),
              failed: 'No maps app found.',
            ),
          ),
        ),
        if (c.hasPoint)
          outlined(
            Icons.copy_rounded,
            'Copy coordinates',
            () => unawaited(_copy(c.coordinates, what: 'Coordinates copied')),
          ),
      ],
      EventContent() => [
        filled(
          Icons.event_available_rounded,
          'Add to calendar',
          () => unawaited(_shareFile(c.toIcs(), 'ics', c.summary)),
        ),
      ],
      OtpAuthContent() => [
        filled(
          Icons.shield_rounded,
          'Add to Authenticator',
          () => unawaited(_addToAuthenticator()),
        ),
      ],
      PaymentContent() => [
        if (c.account != null)
          outlined(
            Icons.copy_rounded,
            'Copy ${c.accountLabel.toLowerCase()}',
            () => unawaited(_copy(c.account!.replaceAll(' ', ''))),
          ),
      ],
      ProductContent() => [
        filled(
          Icons.copy_rounded,
          'Copy number',
          () => unawaited(_copy(c.number, what: 'Number copied')),
        ),
      ],
      IdCardContent() => const [],
      TextContent() => [
        filled(
          Icons.copy_rounded,
          'Copy text',
          () => unawaited(_copy(c.raw, what: 'Text copied')),
        ),
      ],
    };
  }

  String? _note() => switch (content) {
    WifiContent() => CodeResultScreen.wifiJoinNote,
    PaymentContent() => CodeResultScreen.paymentNote,
    IdCardContent() => CodeResultScreen.idCardNote,
    OtpAuthContent() => CodeResultScreen.otpNote,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = content;
    final note = _note();
    final fields = c.fields;
    final canSaveNote = c is! OtpAuthContent;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        actions: [
          if (c is! OtpAuthContent)
            IconButton(
              tooltip: 'Copy all',
              onPressed: () => unawaited(_copy(c.toPlainText())),
              icon: const Icon(Icons.copy_all_rounded),
            ),
          IconButton(
            tooltip: 'Share',
            onPressed: _shareText,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x10),
        children: [
          ListTile(
            leading: IconBadge(kindIcon(c.kind)),
            title: Text(
              c.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium,
            ),
            subtitle: Text(widget.code.symbology.label),
          ),
          if (c case UrlContent(:final safety) when safety.hasWarnings)
            _WarningCard(safety),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.x2,
                Space.gutter,
                0,
              ),
              child: Text(
                note,
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
          const SectionHeader('Details'),
          for (var i = 0; i < fields.length; i++)
            _FieldTile(
              field: fields[i],
              revealed: _revealed.contains(i),
              onReveal: () => setState(
                () => _revealed.contains(i)
                    ? _revealed.remove(i)
                    : _revealed.add(i),
              ),
              onCopy: () => unawaited(
                _copy(fields[i].value, what: '${fields[i].label} copied'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x5,
              Space.gutter,
              0,
            ),
            child: Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              children: [
                ..._primaryActions(),
                if (canSaveNote)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _saveToVault,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Save to ID Vault'),
                  ),
              ],
            ),
          ),
          if (c is! OtpAuthContent && c is! TextContent)
            ExpansionTile(
              title: const Text('Raw content'),
              childrenPadding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.x3,
              ),
              children: [
                SelectableText(
                  widget.code.raw,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.field,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
  });

  final CodeField field;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final hidden = field.secret && !revealed;
    return ListTile(
      title: Text(
        field.label,
        style: context.text.labelMedium?.copyWith(
          color: context.ds.textSecondary,
        ),
      ),
      subtitle: hidden
          ? Text('•' * field.value.length.clamp(6, 16))
          : SelectableText(field.value, style: context.text.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (field.secret)
            IconButton(
              tooltip: revealed ? 'Hide ${field.label}' : 'Show ${field.label}',
              onPressed: onReveal,
              icon: Icon(
                revealed
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          IconButton(
            tooltip: 'Copy ${field.label}',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard(this.safety);

  final UrlSafetyReport safety;

  @override
  Widget build(BuildContext context) {
    final severe = safety.isSuspicious;
    final color = severe ? context.colors.error : context.ds.textSecondary;
    return Card(
      margin: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        0,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  severe ? Icons.gpp_maybe_rounded : Icons.info_outline_rounded,
                  color: color,
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    severe ? 'Be careful with this link' : 'Before you open it',
                    style: context.text.titleSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            for (final w in safety.warnings) ...[
              const SizedBox(height: Space.x2),
              Text(w.title, style: context.text.labelLarge),
              Text(w.detail, style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
