/// What an engine can do on this device, reported honestly so the UI never
/// implies a feature ran locally when it could not (PRD FR-09, FR-11).
class EngineCapability {
  const EngineCapability({
    required this.available,
    required this.worksOffline,
    this.requiresDownload = false,
    this.note,
  });

  static const unavailable = EngineCapability(
    available: false,
    worksOffline: false,
  );

  final bool available;
  final bool worksOffline;

  /// True when a model/module is fetched by the OS on first use (e.g. the
  /// Google Play services delivered ML Kit document scanner).
  final bool requiresDownload;
  final String? note;
}
