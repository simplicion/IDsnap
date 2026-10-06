/// Pure-Dart QR and barcode payloads: parsing (Wi-Fi, contacts, links,
/// email, phone, SMS, locations, calendar events, sign-in keys, payment
/// requests, product and ID card barcodes), offline link-safety checks and
/// a QR encoder with PNG export. No network, no platform code.
library;

export 'src/content.dart';
export 'src/generator.dart' show QrErrorLevel, QrMatrix, QrPayload;
export 'src/parser.dart' show CodeParser;
export 'src/parsers/id_card.dart' show formatCardDate;
export 'src/parsers/payment.dart' show formatIban, isValidIban;
export 'src/parsers/product.dart' show expandUpcE, gtinCheckDigit, isValidGtin;
export 'src/symbology.dart';
export 'src/url_safety.dart';
