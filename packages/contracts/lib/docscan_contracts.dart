/// Composition contracts: one Riverpod provider per domain port (overridden
/// with concrete adapters in each app's bootstrap), shared use cases, the
/// settings controller, and the navigation contract between features.
library;

export 'src/providers.dart';
export 'src/routes.dart';
export 'src/settings_controller.dart';
