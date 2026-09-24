import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:meta/meta.dart';

/// Non-destructive enhancement presets (PRD FR-03).
enum EnhancementFilter {
  original('Original'),
  enhanced('Auto enhance'),
  grayscale('Grayscale'),
  blackWhite('Black & white'),
  noShadow('Remove shadows');

  const EnhancementFilter(this.label);
  final String label;
}

/// Edits are parameters applied at render time. The original image is never
/// modified, so every edit is reversible.
@immutable
class PageEdits {
  const PageEdits({
    this.quad,
    this.quarterTurns = 0,
    this.filter = EnhancementFilter.enhanced,
    this.brightness = 0,
    this.contrast = 0,
  });

  factory PageEdits.fromJson(Map<String, dynamic> j) => PageEdits(
    quad: j['quad'] == null ? null : Quad.fromJson(j['quad'] as List<dynamic>),
    quarterTurns: (j['quarterTurns'] as int?) ?? 0,
    filter:
        EnhancementFilter.values.asNameMap()[j['filter']] ??
        EnhancementFilter.enhanced,
    brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
    contrast: (j['contrast'] as num?)?.toDouble() ?? 0,
  );

  /// Page corners; `null` means no perspective correction.
  final Quad? quad;

  /// Clockwise rotation in 90° steps, applied after cropping.
  final int quarterTurns;
  final EnhancementFilter filter;

  /// -1..1 adjustments applied after the filter.
  final double brightness;
  final double contrast;

  PageEdits copyWith({
    Quad? quad,
    bool clearQuad = false,
    int? quarterTurns,
    EnhancementFilter? filter,
    double? brightness,
    double? contrast,
  }) => PageEdits(
    quad: clearQuad ? null : quad ?? this.quad,
    quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
  );

  Map<String, dynamic> toJson() => {
    'quad': quad?.toJson(),
    'quarterTurns': quarterTurns,
    'filter': filter.name,
    'brightness': brightness,
    'contrast': contrast,
  };

  @override
  bool operator ==(Object other) =>
      other is PageEdits &&
      other.quad == quad &&
      other.quarterTurns == quarterTurns &&
      other.filter == filter &&
      other.brightness == brightness &&
      other.contrast == contrast;

  @override
  int get hashCode =>
      Object.hash(quad, quarterTurns, filter, brightness, contrast);
}

/// One captured page in a scan draft.
@immutable
class ScanPage {
  const ScanPage({
    required this.id,
    required this.originalPath,
    this.edits = const PageEdits(),
    this.autoDetected = false,
  });

  factory ScanPage.fromJson(Map<String, dynamic> j) => ScanPage(
    id: j['id'] as String,
    originalPath: j['originalPath'] as String,
    edits: PageEdits.fromJson(j['edits'] as Map<String, dynamic>),
    autoDetected: (j['autoDetected'] as bool?) ?? false,
  );

  final String id;

  /// Absolute path of the untouched captured image (app-private storage).
  final String originalPath;
  final PageEdits edits;

  /// True when [edits.quad] came from automatic detection, not the user.
  final bool autoDetected;

  ScanPage copyWith({PageEdits? edits, bool? autoDetected}) => ScanPage(
    id: id,
    originalPath: originalPath,
    edits: edits ?? this.edits,
    autoDetected: autoDetected ?? this.autoDetected,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'edits': edits.toJson(),
    'autoDetected': autoDetected,
  };
}

/// An unsaved multi-page scan. Persisted so it survives process death.
@immutable
class ScanDraft {
  const ScanDraft({
    required this.id,
    required this.pages,
    required this.createdAt,
  });

  factory ScanDraft.fromJson(Map<String, dynamic> j) => ScanDraft(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    pages: [
      for (final p in j['pages'] as List<dynamic>)
        ScanPage.fromJson(p as Map<String, dynamic>),
    ],
  );

  final String id;
  final List<ScanPage> pages;
  final DateTime createdAt;

  bool get isEmpty => pages.isEmpty;

  ScanDraft copyWith({List<ScanPage>? pages}) =>
      ScanDraft(id: id, pages: pages ?? this.pages, createdAt: createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
  };
}
