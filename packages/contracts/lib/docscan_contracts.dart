/// Composition contracts: one Riverpod provider per domain port (overridden
/// with concrete adapters in each app's bootstrap), shared use cases, the
/// settings controller, and the navigation contract between features.
library;

export 'src/ad_placement.dart';
export 'src/ad_widgets.dart';
export 'src/ads.dart';
export 'src/backup_flows.dart';
export 'src/entitlements.dart';
export 'src/expiry_reminders.dart';
export 'src/monetization.dart';
export 'src/pro_gate.dart';
export 'src/providers.dart';
export 'src/routes.dart';
export 'src/save_destination.dart';
export 'src/settings_controller.dart';
