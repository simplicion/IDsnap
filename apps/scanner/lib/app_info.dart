import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

/// App version shown to support. Must equal `version:` in pubspec.yaml
/// (test/overrides_coverage_test.dart fails when they drift apart).
const appVersion = '1.0.0+2';

/// Support contact for failure screens (audit M-04). The address comes from
/// `--dart-define=IDSNAP_SUPPORT_EMAIL=you@yourdomain`; the default is a
/// placeholder (support@example.com) that MUST be replaced for release.
/// Opening the email app is a user action handed to another app; IDSnap
/// itself sends nothing (ADR-0008).
void configureSupportContact() {
  SupportContact.appVersion = appVersion;
  SupportContact.launcher = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
