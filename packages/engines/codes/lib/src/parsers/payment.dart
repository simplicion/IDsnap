import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/text_utils.dart';

/// Bank-transfer payment QR (the "BCD" line format), `payto://iban/…`
/// (RFC 8905) and `upi://pay?…`-style payment-app links. Read-only.
PaymentContent? parsePayment(String raw) =>
    _parseBcd(raw) ?? _parsePayto(raw) ?? _parsePayLink(raw);

PaymentContent? _parseBcd(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  if (lines.length < 7 || lines.first.trim() != 'BCD') return null;
  String? at(int i) => i < lines.length ? cleanOrNull(lines[i]) : null;
  final service = at(3)?.toUpperCase();
  if (service != 'SCT' && service != 'INST') return null;
  final iban = at(6)?.replaceAll(' ', '').toUpperCase();
  if (iban == null) return null;
  final amountText = at(7);
  String? currency;
  String? amount;
  if (amountText != null) {
    final m = RegExp(
      r'^([A-Za-z]{3})\s*(\d+(?:[.,]\d{1,2})?)$',
    ).firstMatch(amountText);
    if (m != null) {
      currency = m.group(1)!.toUpperCase();
      amount = _money(m.group(2)!);
    } else {
      amount = amountText;
    }
  }
  final purpose = at(8);
  return PaymentContent(
    raw,
    method: PaymentMethod.bankTransfer,
    payeeName: at(5),
    account: formatIban(iban),
    accountLabel: 'IBAN',
    accountValid: isValidIban(iban),
    bic: at(4),
    amount: amount,
    currency: currency,
    reference: at(9),
    message: at(10),
    extra: [
      if (purpose != null) CodeField('Purpose code', purpose),
      if (at(11) != null) CodeField('Note to payer', at(11)!),
    ],
  );
}

PaymentContent? _parsePayto(String raw) {
  final rest = stripPrefixIgnoreCase(raw.trim(), 'payto://');
  if (rest == null) return null;
  final q = rest.indexOf('?');
  final path = (q < 0 ? rest : rest.substring(0, q)).split('/');
  final params = q < 0 ? <String, String>{} : parseQuery(rest.substring(q + 1));
  if (path.isEmpty) return null;
  final target = path.first.toLowerCase();
  String? account;
  String? bic;
  bool? valid;
  var label = 'Payee account';
  if (target == 'iban') {
    // payto://iban/<BIC>/<IBAN> or payto://iban/<IBAN>
    final parts = path.skip(1).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final iban = parts.last.replaceAll(' ', '').toUpperCase();
    if (parts.length > 1) bic = parts.first.toUpperCase();
    account = formatIban(iban);
    valid = isValidIban(iban);
    label = 'IBAN';
  } else {
    account = cleanOrNull(safeDecodeComponent(path.skip(1).join('/')));
  }
  String? currency;
  String? amount;
  final amountText = params['amount'];
  if (amountText != null) {
    final c = amountText.indexOf(':');
    if (c > 0) {
      currency = amountText.substring(0, c).toUpperCase();
      amount = _money(amountText.substring(c + 1));
    } else {
      amount = amountText;
    }
  }
  return PaymentContent(
    raw,
    method: PaymentMethod.bankTransfer,
    payeeName: cleanOrNull(params['receiver-name']),
    account: account,
    accountLabel: label,
    accountValid: valid,
    bic: bic ?? cleanOrNull(params['bic']),
    amount: amount,
    currency: currency,
    message: cleanOrNull(params['message']),
    reference: cleanOrNull(params['instruction']),
  );
}

/// `<scheme>://pay?pa=<payee address>&pn=<name>&am=<amount>&cu=<currency>…`
PaymentContent? _parsePayLink(String raw) {
  final t = raw.trim();
  final m = RegExp(
    r'^([a-z][a-z0-9+.-]*)://pay\?(.*)$',
    caseSensitive: false,
  ).firstMatch(t);
  if (m == null) return null;
  final scheme = m.group(1)!.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return null;
  final params = parseQuery(m.group(2)!, plusAsSpace: true);
  final payee = cleanOrNull(params['pa']);
  if (payee == null) return null;
  final amount = cleanOrNull(params['am']);
  return PaymentContent(
    raw,
    method: PaymentMethod.paymentLink,
    payeeName: cleanOrNull(params['pn']),
    account: payee,
    accountLabel: 'Payee address',
    amount: amount == null ? null : _money(amount),
    currency: cleanOrNull(params['cu'])?.toUpperCase(),
    reference: cleanOrNull(params['tr']),
    message: cleanOrNull(params['tn']),
    extra: [
      if (cleanOrNull(params['mam']) != null)
        CodeField('Minimum amount', params['mam']!.trim()),
      if (cleanOrNull(params['tid']) != null)
        CodeField('Transaction ID', params['tid']!.trim()),
      if (cleanOrNull(params['mc']) != null)
        CodeField('Merchant category code', params['mc']!.trim()),
      if (cleanOrNull(params['url']) != null)
        CodeField('Reference link', params['url']!.trim()),
    ],
  );
}

String _money(String value) {
  final normalized = value.replaceAll(',', '.');
  final d = double.tryParse(normalized);
  return d == null ? value : d.toStringAsFixed(2);
}

/// IBAN checksum (ISO 13616, mod 97).
bool isValidIban(String input) {
  final iban = input.replaceAll(' ', '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(iban)) return false;
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var remainder = 0;
  for (final unit in rearranged.codeUnits) {
    final digits = unit >= 65 ? '${unit - 55}' : String.fromCharCode(unit);
    for (final d in digits.codeUnits) {
      remainder = (remainder * 10 + (d - 48)) % 97;
    }
  }
  return remainder == 1;
}

/// Groups an IBAN in blocks of four for reading.
String formatIban(String iban) {
  final b = StringBuffer();
  for (var i = 0; i < iban.length; i += 4) {
    if (i > 0) b.write(' ');
    b.write(iban.substring(i, i + 4 > iban.length ? iban.length : i + 4));
  }
  return b.toString();
}
