import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/text_utils.dart';

/// ID card PDF417 barcodes that use the widely adopted "ANSI" card data
/// format: a header (`@`, `ANSI `, issuer ID number, version) followed by
/// three-letter data elements (`DCS` family name, `DBB` date of birth…).
/// Every element is mapped to a generic label.
IdCardContent? parseIdCard(String raw, {bool fromPdf417 = false}) {
  final text = raw.trimLeft();
  final headerAt = _headerIndex(text);
  final hasHeader = text.startsWith('@') && headerAt >= 0;
  if (!hasHeader && !fromPdf417) return null;

  String? issuerId;
  String? version;
  if (headerAt >= 0) {
    final m = RegExp(
      r'^(?:ANSI |AAMVA)\s?(\d{6})(\d{2})',
    ).firstMatch(text.substring(headerAt));
    if (m != null) {
      issuerId = m.group(1);
      version = m.group(2);
    }
  }

  String? documentType;
  final subfile = RegExp(
    '(DL|ID)(?=D[A-Z]{2})',
  ).firstMatch(headerAt >= 0 ? text.substring(headerAt) : text);
  if (subfile != null) {
    documentType = subfile.group(1) == 'DL'
        ? 'Driving licence'
        : 'Identification card';
  }

  final elements = <String, String>{};
  for (final segment in text.split(RegExp('[\n\r\x1c\x1d\x1e]'))) {
    var s = segment.trim();
    if (!RegExp('^D[A-Z]{2}').hasMatch(s) || !_known(s.substring(0, 3))) {
      final m = RegExp('(?:DL|ID)(D[A-Z]{2})').firstMatch(s);
      if (m == null) continue;
      s = s.substring(m.start + 2);
    }
    if (s.length < 3) continue;
    final code = s.substring(0, 3);
    if (!_known(code)) continue;
    final value = s.substring(3).trim();
    if (value.isEmpty) continue;
    elements.putIfAbsent(code, () => value);
  }
  // Without a header, only accept a clear set of identity elements.
  final identity = {'DAQ', 'DCS', 'DAA', 'DAB', 'DBB', 'DAC'};
  final identityCount = elements.keys.where(identity.contains).length;
  if (elements.length < 2 || (!hasHeader && identityCount < 2)) return null;

  final fields = <CodeField>[];
  for (final entry in _labels.entries) {
    final value = elements[entry.key];
    if (value == null) continue;
    final shown = _format(entry.key, value);
    if (shown == null || shown.isEmpty) continue;
    fields.add(CodeField(entry.value, shown));
  }
  if (fields.isEmpty) return null;
  return IdCardContent(
    raw,
    documentFields: fields,
    documentType: documentType,
    issuerId: issuerId,
    standardVersion: version,
  );
}

int _headerIndex(String text) {
  final head = text.length > 40 ? text.substring(0, 40) : text;
  final ansi = head.indexOf('ANSI ');
  return ansi >= 0 ? ansi : head.indexOf('AAMVA');
}

bool _known(String code) =>
    _labels.containsKey(code) || _ignored.contains(code);

/// Display order and generic labels.
const _labels = <String, String>{
  'DAA': 'Full name',
  'DCS': 'Family name',
  'DAB': 'Family name',
  'DAC': 'Given name',
  'DCT': 'Given names',
  'DAD': 'Middle names',
  'DCU': 'Name suffix',
  'DAQ': 'ID number',
  'DBB': 'Date of birth',
  'DBD': 'Issue date',
  'DBA': 'Expiry date',
  'DBC': 'Sex',
  'DAU': 'Height',
  'DAW': 'Weight',
  'DAX': 'Weight',
  'DAY': 'Eye colour',
  'DAZ': 'Hair colour',
  'DAG': 'Address',
  'DAL': 'Address',
  'DAH': 'Address line 2',
  'DAM': 'Address line 2',
  'DAI': 'City',
  'DAN': 'City',
  'DAJ': 'Region',
  'DAO': 'Region',
  'DAK': 'Postal code',
  'DAP': 'Postal code',
  'DCG': 'Country',
  'DCI': 'Place of birth',
  'DCA': 'Vehicle class',
  'DCB': 'Restrictions',
  'DCD': 'Endorsements',
  'DCF': 'Document discriminator',
  'DCK': 'Inventory control number',
  'DDB': 'Card revision date',
  'DDK': 'Organ donor',
  'DDL': 'Veteran',
};

/// Recognized elements that aren't shown (flags, audit data).
const _ignored = {
  'DDE',
  'DDF',
  'DDG',
  'DDA',
  'DDC',
  'DDD',
  'DDH',
  'DDI',
  'DDJ',
  'DCJ',
  'DCL',
  'DBN',
  'DBG',
  'DBS',
  'DCE',
  'DCM',
  'DCN',
  'DCO',
  'DCP',
  'DCQ',
  'DCR',
  'DBE',
  'DBF',
  'DBH',
  'DBI',
  'DBJ',
  'DBK',
  'DBL',
  'DBM',
  'DBO',
  'DBP',
  'DBQ',
  'DBR',
  'DAE',
  'DAF',
  'DAR',
  'DAS',
  'DAT',
  'DAV',
};

String? _format(String code, String value) {
  switch (code) {
    case 'DBB' || 'DBD' || 'DBA' || 'DDB':
      return formatCardDate(value);
    case 'DBC':
      return switch (value.toUpperCase()) {
        '1' || 'M' => 'Male',
        '2' || 'F' => 'Female',
        '9' || 'X' => 'Not specified',
        _ => value,
      };
    case 'DAU':
      final m = RegExp(
        r'^0*(\d+)\s*(IN|CM)$',
        caseSensitive: false,
      ).firstMatch(value);
      return m == null ? value : '${m.group(1)} ${m.group(2)!.toLowerCase()}';
    case 'DAW':
      return '${value.replaceFirst(RegExp('^0+(?=.)'), '')} lb';
    case 'DAX':
      return '${value.replaceFirst(RegExp('^0+(?=.)'), '')} kg';
    case 'DAY' || 'DAZ':
      return _colours[value.toUpperCase()] ?? value;
    case 'DAA':
      return value
          .split(RegExp(r'[,$]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(' ');
    case 'DDK' || 'DDL':
      return value == '1' ? 'Yes' : null;
    case 'DAK' || 'DAP':
      // 9-digit postal codes are stored without a separator, padded with 0s.
      final m = RegExp(r'^(\d{5})(\d{4})$').firstMatch(value);
      if (m == null) return value;
      return m.group(2) == '0000' ? m.group(1) : '${m.group(1)}-${m.group(2)}';
    default:
      return cleanOrNull(value);
  }
}

/// `MMDDCCYY` or `CCYYMMDD` → `YYYY-MM-DD`; other values unchanged.
String formatCardDate(String value) {
  final v = value.trim();
  if (!RegExp(r'^\d{8}$').hasMatch(v)) return v;
  bool valid(int y, int m, int d) =>
      y >= 1800 && y <= 2200 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
  final y1 = int.parse(v.substring(0, 4));
  final m1 = int.parse(v.substring(4, 6));
  final d1 = int.parse(v.substring(6, 8));
  if (valid(y1, m1, d1)) {
    return '${v.substring(0, 4)}-${v.substring(4, 6)}-${v.substring(6, 8)}';
  }
  final m2 = int.parse(v.substring(0, 2));
  final d2 = int.parse(v.substring(2, 4));
  final y2 = int.parse(v.substring(4, 8));
  if (valid(y2, m2, d2)) {
    return '${v.substring(4, 8)}-${v.substring(0, 2)}-${v.substring(2, 4)}';
  }
  return v;
}

const _colours = {
  'BLK': 'Black',
  'BLU': 'Blue',
  'BRO': 'Brown',
  'GRY': 'Grey',
  'GRN': 'Green',
  'HAZ': 'Hazel',
  'MAR': 'Maroon',
  'PNK': 'Pink',
  'DIC': 'Dichromatic',
  'BAL': 'Bald',
  'BLN': 'Blond',
  'RED': 'Red',
  'SDY': 'Sandy',
  'WHI': 'White',
  'UNK': 'Unknown',
};
