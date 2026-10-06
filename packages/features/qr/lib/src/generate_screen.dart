import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/src/services.dart';
import 'package:feature_qr/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum QrGenerateType {
  text('Text', Icons.notes_rounded),
  url('Link', Icons.link_rounded),
  wifi('Wi-Fi', Icons.wifi_rounded),
  contact('Contact', Icons.contact_page_rounded),
  email('Email', Icons.email_rounded),
  phone('Phone', Icons.phone_rounded),
  sms('SMS', Icons.sms_rounded);

  const QrGenerateType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Export sizes offered for the PNG, in pixels.
const qrExportSizes = [512, 1024, 2048];

/// Creates QR codes on the phone (pure-Dart encoder) and exports PNGs.
class QrGenerateScreen extends ConsumerStatefulWidget {
  const QrGenerateScreen({super.key});

  static const tooLong =
      'Too much data for one QR code. Shorten it or lower the error '
      'correction.';

  @override
  ConsumerState<QrGenerateScreen> createState() => _QrGenerateScreenState();
}

class _QrGenerateScreenState extends ConsumerState<QrGenerateScreen> {
  QrGenerateType _type = QrGenerateType.text;
  QrErrorLevel _level = QrErrorLevel.medium;
  int _pixels = 1024;
  WifiSecurity _security = WifiSecurity.wpa;
  bool _hidden = false;
  bool _busy = false;

  final _c = <String, TextEditingController>{};

  TextEditingController _field(String key) =>
      _c.putIfAbsent(key, TextEditingController.new);

  String _v(String key) => _c[key]?.text.trim() ?? '';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The payload for the current form, or null while it's incomplete.
  String? _payload() {
    switch (_type) {
      case QrGenerateType.text:
        final t = _c['text']?.text ?? '';
        return t.trim().isEmpty ? null : t;
      case QrGenerateType.url:
        return _v('url').isEmpty ? null : QrPayload.url(_v('url'));
      case QrGenerateType.wifi:
        if (_v('ssid').isEmpty) return null;
        return QrPayload.wifi(
          ssid: _c['ssid']!.text,
          password: _c['password']?.text ?? '',
          security: _security,
          hidden: _hidden,
        );
      case QrGenerateType.contact:
        if (_v('given').isEmpty &&
            _v('family').isEmpty &&
            _v('org').isEmpty &&
            _v('tel').isEmpty &&
            _v('mail').isEmpty) {
          return null;
        }
        String? opt(String k) => _v(k).isEmpty ? null : _v(k);
        return QrPayload.contact(
          ContactCard(
            givenName: opt('given'),
            familyName: opt('family'),
            organization: opt('org'),
            jobTitle: opt('title'),
            phones: [if (opt('tel') != null) LabeledValue(opt('tel')!)],
            emails: [if (opt('mail') != null) LabeledValue(opt('mail')!)],
            urls: [if (opt('web') != null) LabeledValue(opt('web')!)],
            addresses: [if (opt('adr') != null) LabeledValue(opt('adr')!)],
          ),
        );
      case QrGenerateType.email:
        if (_v('to').isEmpty) return null;
        return QrPayload.email(
          to: _v('to'),
          subject: _v('subject'),
          body: _c['body']?.text,
        );
      case QrGenerateType.phone:
        return _v('phone').isEmpty ? null : QrPayload.phone(_v('phone'));
      case QrGenerateType.sms:
        if (_v('smsTo').isEmpty) return null;
        return QrPayload.sms(number: _v('smsTo'), message: _c['smsBody']?.text);
    }
  }

  String get _fileName => 'qr-${_type.name}.png';

  Future<void> _export(
    Future<void> Function(QrActions actions, Uint8List png) run,
  ) async {
    final payload = _payload();
    final matrix = payload == null
        ? null
        : QrMatrix.tryEncode(payload, level: _level);
    if (matrix == null) return;
    setState(() => _busy = true);
    final png = await _renderPng(matrix, _pixels);
    try {
      await run(ref.read(qrActionsProvider), png);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _export((a, png) async {
    final r = await a.shareFile(png, extension: 'png', subject: 'QR code');
    if (r case Err(:final failure) when mounted) {
      showFailureSnack(context, failure);
    }
  });

  Future<void> _save() => _export((a, png) async {
    final r = await a.saveToDevice(png, _fileName);
    if (!mounted) return;
    r.fold(
      (saved) => saved ? showAppSnack(context, 'PNG saved') : null,
      (f) => showFailureSnack(context, f),
    );
  });

  Future<void> _vault() async {
    if (!await pickQrSaveFolder(context, ref) || !mounted) return;
    await _export((a, png) async {
      final r = await a.saveToVault(
        png,
        format: DocumentFormat.png,
        name: 'QR code – ${_type.label}',
        folderId: ref.read(saveFolderProvider(qrSaveFlow)),
      );
      if (!mounted) return;
      r.fold(
        (doc) => showAppSnack(
          context,
          'Saved to '
          '${saveFolderLabel(ref.read(saveFolderTreeProvider).value, doc.folderId)}',
        ),
        (f) => showFailureSnack(context, f),
      );
    });
  }

  Widget _text(
    String key,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: TextField(
      key: ValueKey('qr-field-$key'),
      controller: _field(key),
      decoration: InputDecoration(labelText: label, hintText: hint),
      keyboardType: keyboard,
      maxLines: maxLines,
      minLines: 1,
      obscureText: obscure,
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      onChanged: (_) => setState(() {}),
    ),
  );

  List<Widget> _form() => switch (_type) {
    QrGenerateType.text => [
      _text('text', 'Text', maxLines: 6, keyboard: TextInputType.multiline),
    ],
    QrGenerateType.url => [
      _text(
        'url',
        'Link',
        hint: 'https://example.com',
        keyboard: TextInputType.url,
      ),
    ],
    QrGenerateType.wifi => [
      _text('ssid', 'Network name'),
      if (_security != WifiSecurity.open)
        _text('password', 'Password', keyboard: TextInputType.visiblePassword),
      DropdownButtonFormField<WifiSecurity>(
        initialValue: _security,
        decoration: const InputDecoration(labelText: 'Security'),
        items: [
          for (final s in [
            WifiSecurity.wpa,
            WifiSecurity.wep,
            WifiSecurity.open,
          ])
            DropdownMenuItem(value: s, child: Text(s.label)),
        ],
        onChanged: (s) => setState(() => _security = s ?? _security),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Hidden network'),
        value: _hidden,
        onChanged: (v) => setState(() => _hidden = v),
      ),
    ],
    QrGenerateType.contact => [
      _text('given', 'First name'),
      _text('family', 'Last name'),
      _text('org', 'Organization'),
      _text('title', 'Job title'),
      _text('tel', 'Phone', keyboard: TextInputType.phone),
      _text('mail', 'Email', keyboard: TextInputType.emailAddress),
      _text('web', 'Website', keyboard: TextInputType.url),
      _text('adr', 'Address', maxLines: 3),
    ],
    QrGenerateType.email => [
      _text('to', 'To', keyboard: TextInputType.emailAddress),
      _text('subject', 'Subject'),
      _text('body', 'Message', maxLines: 5),
    ],
    QrGenerateType.phone => [
      _text('phone', 'Phone number', keyboard: TextInputType.phone),
    ],
    QrGenerateType.sms => [
      _text('smsTo', 'Phone number', keyboard: TextInputType.phone),
      _text('smsBody', 'Message', maxLines: 4),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final payload = _payload();
    final matrix = payload == null
        ? null
        : QrMatrix.tryEncode(payload, level: _level);
    final ready = matrix != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Create QR code')),
      // Free build only; empty otherwise, and hidden while typing
      // (ADR-0013).
      bottomNavigationBar: const AdBannerSlot(),
      // Not lazy: the form is short and the preview must always exist.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              children: [
                for (final t in QrGenerateType.values)
                  ChoiceChip(
                    avatar: Icon(t.icon, size: 18),
                    label: Text(t.label),
                    selected: t == _type,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: Space.x4),
            ..._form(),
            const SizedBox(height: Space.x3),
            Text('Error correction', style: context.text.labelLarge),
            const SizedBox(height: Space.x2),
            SegmentedButton<QrErrorLevel>(
              segments: [
                for (final l in QrErrorLevel.values)
                  ButtonSegment(
                    value: l,
                    label: Text(l.label),
                    tooltip: 'Survives ${l.recovery} damage',
                  ),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _level = s.single),
            ),
            const SizedBox(height: Space.x3),
            Text('Image size', style: context.text.labelLarge),
            const SizedBox(height: Space.x2),
            SegmentedButton<int>(
              segments: [
                for (final p in qrExportSizes)
                  ButtonSegment(value: p, label: Text('$p px')),
              ],
              selected: {_pixels},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _pixels = s.single),
            ),
            const SizedBox(height: Space.x5),
            Center(
              child: payload == null
                  ? Text(
                      'Fill in the details to see your QR code.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.ds.textSecondary,
                      ),
                    )
                  : matrix == null
                  ? Text(
                      QrGenerateScreen.tooLong,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.error,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : QrMatrixView(matrix),
            ),
            const SizedBox(height: Space.x5),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: ready ? () => unawaited(_share()) : null,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share PNG'),
                ),
                OutlinedButton.icon(
                  onPressed: ready ? () => unawaited(_save()) : null,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Save PNG'),
                ),
                OutlinedButton.icon(
                  onPressed: ready ? () => unawaited(_vault()) : null,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Add to ID Vault'),
                ),
              ],
            ),
            if (_type == QrGenerateType.wifi)
              Padding(
                padding: const EdgeInsets.only(top: Space.x4),
                child: Text(
                  'Anyone who scans this code can read the Wi-Fi password.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Top level so the isolate closure captures only the matrix and size.
Future<Uint8List> _renderPng(QrMatrix matrix, int pixels) =>
    runHeavy(() => matrix.toPng(pixels: pixels));
