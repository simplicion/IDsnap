import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/parsers/content_lines.dart';
import 'package:engine_codes/src/text_utils.dart';

/// A `VEVENT` (optionally inside a `VCALENDAR`). Null without one.
EventContent? parseEvent(String raw) {
  if (!raw.toUpperCase().contains('BEGIN:VEVENT')) return null;
  final lines = parseContentLines(raw);
  final block = <String>[];
  var inEvent = false;
  var nested = 0;
  String? summary;
  String? location;
  String? description;
  String? organizer;
  String? url;
  EventTime? start;
  EventTime? end;
  Duration? duration;

  for (final line in lines) {
    final v = line.rawValue.trim().toUpperCase();
    if (line.name == 'BEGIN' && v == 'VEVENT') {
      if (inEvent) break;
      inEvent = true;
      block.add('BEGIN:VEVENT');
      continue;
    }
    if (!inEvent) continue;
    if (line.name == 'END' && v == 'VEVENT' && nested == 0) {
      block.add('END:VEVENT');
      inEvent = false;
      break;
    }
    block.add(line.text);
    // Skip properties of nested components (VALARM).
    if (line.name == 'BEGIN') nested++;
    if (line.name == 'END' && nested > 0) nested--;
    if (nested > 0) continue;
    final value = cleanOrNull(line.value);
    switch (line.name) {
      case 'SUMMARY':
        summary ??= value;
      case 'LOCATION':
        location ??= value;
      case 'DESCRIPTION':
        description ??= value;
      case 'URL':
        url ??= value;
      case 'ORGANIZER':
        final cn = line.param('CN');
        final mail = value == null
            ? null
            : (stripPrefixIgnoreCase(value, 'mailto:') ?? value);
        organizer ??= cleanOrNull(
          cn != null && mail != null ? '$cn <$mail>' : (cn ?? mail),
        );
      case 'DTSTART':
        start ??= parseEventTime(line);
      case 'DTEND':
        end ??= parseEventTime(line);
      case 'DURATION':
        duration ??= parseIcsDuration(line.rawValue.trim());
    }
  }
  // A missing END:VEVENT is tolerated.
  if (inEvent) block.add('END:VEVENT');
  if (summary == null && start == null) return null;
  if (end == null && start != null && duration != null) {
    end = EventTime(
      start.value.add(duration),
      allDay: start.allDay,
      utc: start.utc,
      tzid: start.tzid,
    );
  }
  return EventContent(
    raw,
    eventBlock: block,
    summaryText: summary,
    start: start,
    end: end,
    location: location,
    description: description,
    organizer: organizer,
    url: url,
  );
}

final _dateTime = RegExp(
  r'^(\d{4})-?(\d{2})-?(\d{2})(?:T(\d{2}):?(\d{2}):?(\d{2})?(Z)?)?$',
);

/// DTSTART/DTEND values: `20260315`, `20260315T090000`, `…Z`, with
/// `TZID=` or `VALUE=DATE` parameters.
EventTime? parseEventTime(ContentLine line) {
  final m = _dateTime.firstMatch(line.rawValue.trim().toUpperCase());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final month = g(2);
  final day = g(3);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (m.group(4) == null) {
    return EventTime(DateTime.utc(g(1), month, day), allDay: true);
  }
  final hour = g(4);
  final minute = g(5);
  final second = g(6);
  if (hour > 23 || minute > 59 || second > 60) return null;
  return EventTime(
    DateTime.utc(g(1), month, day, hour, minute, second),
    utc: m.group(7) != null,
    tzid: m.group(7) == null ? line.param('TZID') : null,
  );
}

/// ISO 8601 / RFC 5545 durations: `PT1H30M`, `P1D`, `P2W`, `-PT15M`.
Duration? parseIcsDuration(String value) {
  final m = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(value.toUpperCase());
  if (m == null || value.length < 2) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  final d = Duration(
    days: g(2) * 7 + g(3),
    hours: g(4),
    minutes: g(5),
    seconds: g(6),
  );
  return m.group(1) == '-' ? -d : d;
}
