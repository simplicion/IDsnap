import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:flutter/material.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "1 Nov 2026" in local time.
String formatDay(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// "1 Nov 2026, 14:05" in local time.
String formatMoment(DateTime d) {
  final l = d.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${formatDay(l)}, $hh:$mm';
}

String daysLabel(int n) => n == 1 ? '1 day' : '$n days';

/// The payment provider, named once.
const paymentProvider = '180 Pay';

/// How to cancel the monthly plan when the portal can't be opened.
/// VERIFY WITH 180 PAY: the customer-portal flow is documented, but the
/// receipt e-mail wording is an assumption (ADR-0012).
const cancelHowTo =
    'open "Manage or cancel monthly plan" while online, or use the link in '
    'your $paymentProvider receipt e-mail to reach the $paymentProvider '
    'customer portal, then choose Cancel';

/// One honest sentence about the current state.
String statusLine(EntitlementState s, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return switch (s) {
    FreeEntitlement() => freeAppLine,
    TrialEntitlement(:final endsAt) =>
      'Free day: ends in ${formatTimeLeft(endsAt, at)}. Every feature is '
          'unlocked until then.',
    DayPassEntitlement(:final expiresAt) =>
      'Day pass: ends in ${formatTimeLeft(expiresAt, at)} '
          '(${formatMoment(expiresAt)}).',
    MonthlyEntitlement(inGracePeriod: true) =>
      "You have the monthly plan. We haven't confirmed this month's "
          'renewal yet, so everything stays unlocked for a few more days.',
    MonthlyEntitlement() => 'You have the monthly plan.',
    ExpiredEntitlement(reason: LapseReason.trialEnded) =>
      'Your free day has ended.',
    ExpiredEntitlement(reason: LapseReason.dayPassEnded) =>
      'Your day pass has ended.',
    ExpiredEntitlement(reason: LapseReason.subscriptionEnded) =>
      'Your monthly plan has ended.',
    ExpiredEntitlement(reason: LapseReason.clockTampered) =>
      "Your phone's date is earlier than the last time IDSnap checked it, "
          "so your licence can't be verified. Set the correct date and time "
          'to continue.',
    ExpiredEntitlement(reason: LapseReason.notActivated) =>
      'Connect to the internet once to start your free day.',
  };
}

/// The free, ad-supported build (ADR-0013). These screens are closed in
/// that build; the text exists so every state has an honest sentence.
const freeAppTitle = 'IDSnap is free';
const freeAppLine =
    'Every feature is unlocked. IDSnap is free and shows ads on a few '
    'screens.';

const alwaysFreeLine =
    'Always free: opening, sharing and exporting your documents, your '
    'folders, and the Authenticator.';

/// The privacy promise of the PAID modes (licence / store), word for word
/// on the paywall and terms. The free build with ads never shows these
/// screens; its sentence is `adsPrivacyLine` in docscan_contracts.
const networkPrivacyLine =
    'Your documents never leave this phone. IDSnap connects to the internet '
    'only to check your licence and for payments.';

/// What Pro gives, value first.
const proBenefits = <(IconData, String, String)>[
  (
    Icons.assignment_turned_in_rounded,
    'Portal-ready kits',
    'Photo, signature and documents sized for exam, application and job '
        'portals',
  ),
  (
    Icons.compress_rounded,
    'Compress to an exact size',
    'Hit "under 200 KB" upload limits for photos and PDFs',
  ),
  (
    Icons.badge_rounded,
    'ID card copies',
    'Front and back on one page, ready to print or send',
  ),
  (
    Icons.draw_rounded,
    'Signatures',
    'Sign PDFs and make clean, transparent signature images',
  ),
  (
    Icons.lock_rounded,
    'File protection',
    'Password-protect files before you share them',
  ),
  (
    Icons.shield_rounded,
    'Secure vault tools',
    'Scanning, text recognition, PDF and image tools — all on this phone',
  ),
];
