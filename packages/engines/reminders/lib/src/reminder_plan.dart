import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart' show immutable;

/// One scheduled reminder, computed from a document's expiry date.
@immutable
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.at,
    required this.daysBefore,
    required this.title,
    required this.body,
  });

  /// Stable notification id derived from document id + [daysBefore].
  final int id;

  /// Local wall-clock time the reminder fires.
  final DateTime at;
  final int daysBefore;
  final String title;
  final String body;
}

/// Days before expiry at which reminders fire.
const reminderOffsets = [30, 7];

/// Reminders fire at 10:00 local time.
const reminderHour = 10;

/// Stable 31-bit notification id (FNV-1a) so re-scheduling replaces the old
/// reminder instead of duplicating it.
int reminderId(String documentId, int daysBefore) {
  var hash = 0x811c9dc5;
  for (final unit in '$documentId:$daysBefore'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Reminders for [document] that are still in the future relative to [now].
/// Empty when the document has no expiry date.
List<ReminderPlan> planExpiryReminders(Document document, DateTime now) {
  final expiry = document.expiresAt;
  if (expiry == null) return const [];
  final day = DateTime(expiry.year, expiry.month, expiry.day);
  return [
    for (final days in reminderOffsets)
      if (DateTime(day.year, day.month, day.day - days, reminderHour)
          case final at when at.isAfter(now))
        ReminderPlan(
          id: reminderId(document.id, days),
          at: at,
          daysBefore: days,
          title: 'Document expiring in $days days',
          body: '“${document.name}” expires on ${formatDay(day)}.',
        ),
  ];
}

String formatDay(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
