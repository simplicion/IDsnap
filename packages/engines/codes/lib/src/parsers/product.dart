import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/symbology.dart';

final _digits = RegExp(r'^\d+$');

/// Retail product numbers (EAN-13/8, UPC-A/E) and ITF-14 case codes, with
/// check-digit validation. Null when [raw] doesn't fit the symbology.
ProductContent? parseProduct(String raw, CodeSymbology symbology) {
  final number = raw.trim().replaceAll(' ', '');
  if (!_digits.hasMatch(number)) return null;
  switch (symbology) {
    case CodeSymbology.ean13 when number.length == 13:
    case CodeSymbology.ean8 when number.length == 8:
    case CodeSymbology.upcA when number.length == 12:
      return ProductContent(
        raw,
        number: number,
        symbology: symbology,
        checkDigitValid: isValidGtin(number),
        isbn: symbology == CodeSymbology.ean13 ? isbnFor(number) : null,
      );
    case CodeSymbology.upcE when number.length == 8 || number.length == 6:
      final full = number.length == 8 ? number : '0${number}X';
      final expanded = expandUpcE(full);
      final hasCheck = number.length == 8;
      return ProductContent(
        raw,
        number: number,
        symbology: symbology,
        checkDigitValid: hasCheck && expanded != null
            ? isValidGtin(expanded)
            : null,
        expanded: hasCheck ? expanded : null,
      );
    case CodeSymbology.itf when number.length == 14:
      return ProductContent(
        raw,
        number: number,
        symbology: symbology,
        checkDigitValid: isValidGtin(number),
      );
    case _:
      return null;
  }
}

/// GTIN mod-10 check digit (EAN-8/13, UPC-A, GTIN-14).
bool isValidGtin(String number) {
  if (!_digits.hasMatch(number) || number.length < 2) return false;
  final check = gtinCheckDigit(number.substring(0, number.length - 1));
  return check == int.parse(number[number.length - 1]);
}

/// The check digit for [body] (the number without its check digit).
int gtinCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final digit = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10;
}

/// Expands an 8-digit UPC-E (number system, six digits, check) to UPC-A.
/// Null when it can't be expanded (number system other than 0/1).
String? expandUpcE(String upcE) {
  if (upcE.length != 8) return null;
  final ns = upcE[0];
  if (ns != '0' && ns != '1') return null;
  final d = upcE.substring(1, 7);
  final check = upcE[7];
  final last = d[5];
  final String body;
  switch (last) {
    case '0' || '1' || '2':
      body = '${d.substring(0, 2)}${last}0000${d.substring(2, 5)}';
    case '3':
      body = '${d.substring(0, 3)}00000${d.substring(3, 5)}';
    case '4':
      body = '${d.substring(0, 4)}00000${d[4]}';
    default:
      body = '${d.substring(0, 5)}0000$last';
  }
  return '$ns$body$check';
}

/// ISBN for book EANs (978/979). 978 numbers also get their ISBN-10.
String? isbnFor(String ean13) {
  if (ean13.length != 13) return null;
  if (!ean13.startsWith('978') && !ean13.startsWith('979')) return null;
  if (!ean13.startsWith('978')) return ean13;
  final core = ean13.substring(3, 12);
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += (core.codeUnitAt(i) - 48) * (10 - i);
  }
  final c = (11 - sum % 11) % 11;
  return '$ean13 (ISBN-10: $core${c == 10 ? 'X' : c})';
}
