import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/src/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where users can reach a human about a failure (production audit M-04).
///
/// Configured once by the app at startup. The address comes from
/// `--dart-define=IDSNAP_SUPPORT_EMAIL=...`; the default is a placeholder the
/// owner MUST replace before release. The draft contains the app version,
/// the platform and the redacted failure diagnostics (code and exception
/// type only) — never document names, contents or paths. Nothing is sent by
/// the app: the user's own email app opens with a draft they can edit.
abstract final class SupportContact {
  /// Placeholder: replace it with a real, monitored mailbox.
  static const placeholderEmail = 'support@example.com';

  static const configuredEmail = String.fromEnvironment(
    'IDSNAP_SUPPORT_EMAIL',
    defaultValue: placeholderEmail,
  );

  /// Support address shown to users and used for the email draft.
  static String email = configuredEmail;

  /// App version (e.g. `1.0.0+1`), set by the app.
  static String appVersion = 'unknown';

  /// Opens a URI with another app (`url_launcher`'s `launchUrl`), set by the
  /// app. Returns false when nothing could open it. `null` hides "Contact
  /// support" (tests, previews).
  static Future<bool> Function(Uri uri)? launcher;

  /// Whether a "Contact support" action can be offered.
  static bool get available => launcher != null;

  /// The `mailto:` draft for [failure] (or a general question when null).
  static Uri emailUri({AppFailure? failure, String? context}) {
    const intro =
        'Please describe what you were doing (do not include personal details '
        'or document contents):';
    final lines = [
      intro,
      '',
      '',
      '— Technical details (no document contents) —',
      'App: IDSnap $appVersion',
      if (context != null) 'Where: $context',
      if (failure != null) 'Error: ${failure.title}',
      if (failure != null) 'Details: ${failure.diagnostics}',
    ];
    final subject = failure == null
        ? 'IDSnap support'
        : 'IDSnap support: ${failure.code.name}';
    // Uri(queryParameters) encodes spaces as '+', which some mail apps show
    // literally; build the query by hand with %20.
    String enc(String v) => Uri.encodeComponent(v);
    return Uri.parse(
      'mailto:$email?subject=${enc(subject)}&body=${enc(lines.join('\n'))}',
    );
  }

  /// Opens the email draft. When no email app is available, copies the
  /// address and the technical details instead and says so.
  static Future<void> contact(
    BuildContext context, {
    AppFailure? failure,
    String? where,
  }) async {
    final uri = emailUri(failure: failure, context: where);
    var opened = false;
    try {
      opened = await (launcher?.call(uri) ?? Future.value(false));
    } on Object {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await Clipboard.setData(
      ClipboardData(
        text: [
          'Support: $email',
          'App: IDSnap $appVersion',
          if (failure != null) 'Details: ${failure.diagnostics}',
        ].join('\n'),
      ),
    );
    if (context.mounted) {
      showAppSnack(
        context,
        'No email app found. The support address ($email) and the error '
        'details were copied — paste them into a message.',
      );
    }
  }
}
