import 'package:engine_codes/src/text_utils.dart';

/// `KEY:value;KEY2:value2;;` as used by MECARD, MATMSG, MEBKM and WIFI.
/// Keys are upper-cased; values are unescaped (`\;`, `\:`, `\,`, `\`).
/// Surrounding double quotes are removed from values.
List<MapEntry<String, String>> parseKeyValues(String body) {
  final entries = <MapEntry<String, String>>[];
  var i = 0;
  while (i < body.length) {
    final colon = indexOfUnescaped(body, ':', i);
    if (colon < 0) break;
    final key = body.substring(i, colon).trim().toUpperCase();
    var end = indexOfUnescaped(body, ';', colon + 1);
    if (end < 0) end = body.length;
    var value = unescapeBackslashes(body.substring(colon + 1, end));
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (key.isNotEmpty) entries.add(MapEntry(key, value));
    i = end + 1;
    // Skip the empty fields of a `;;` terminator.
    while (i < body.length && body[i] == ';') {
      i++;
    }
  }
  return entries;
}
