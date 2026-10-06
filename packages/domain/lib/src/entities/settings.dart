import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/entities/options.dart';
import 'package:docscan_domain/src/entities/scan.dart';
import 'package:meta/meta.dart';

enum ThemePreference {
  system('Match system'),
  light('Light'),
  dark('Dark');

  const ThemePreference(this.label);
  final String label;
}

@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.quality = QualityPreset.balanced,
    this.pageSize = PdfPageSize.a4,
    this.defaultFilter = EnhancementFilter.enhanced,
    this.ocrScript = OcrScript.latin,
    this.autoDetectEdges = true,
    this.searchablePdf = true,
    this.appLock = false,
    this.lockAfterMinutes = 1,
    this.showPrivacyBanner = true,
    this.hideEmptyCategories = false,
    this.expiryReminders = true,
    this.authenticatorRequireUnlock = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.asNameMap()[name] ?? fallback;
    return AppSettings(
      theme: pick(ThemePreference.values, j['theme'], ThemePreference.system),
      quality: pick(QualityPreset.values, j['quality'], QualityPreset.balanced),
      pageSize: pick(PdfPageSize.values, j['pageSize'], PdfPageSize.a4),
      defaultFilter: pick(
        EnhancementFilter.values,
        j['defaultFilter'],
        EnhancementFilter.enhanced,
      ),
      ocrScript: pick(OcrScript.values, j['ocrScript'], OcrScript.latin),
      autoDetectEdges: (j['autoDetectEdges'] as bool?) ?? true,
      searchablePdf: (j['searchablePdf'] as bool?) ?? true,
      appLock: (j['appLock'] as bool?) ?? false,
      lockAfterMinutes: (j['lockAfterMinutes'] as int?) ?? 1,
      showPrivacyBanner: (j['showPrivacyBanner'] as bool?) ?? true,
      hideEmptyCategories: (j['hideEmptyCategories'] as bool?) ?? false,
      expiryReminders: (j['expiryReminders'] as bool?) ?? true,
      authenticatorRequireUnlock:
          (j['authenticatorRequireUnlock'] as bool?) ?? true,
    );
  }

  final ThemePreference theme;
  final QualityPreset quality;
  final PdfPageSize pageSize;
  final EnhancementFilter defaultFilter;
  final OcrScript ocrScript;
  final bool autoDetectEdges;

  /// Add an invisible OCR text layer when saving scans (Latin script only).
  final bool searchablePdf;

  /// Require biometric / device credential to open DocScan.
  final bool appLock;

  /// Re-lock after this many minutes in the background (0 = immediately).
  final int lockAfterMinutes;
  final bool showPrivacyBanner;
  final bool hideEmptyCategories;
  final bool expiryReminders;

  /// Authenticator codes stay hidden until biometric / device-credential
  /// unlock (when the device supports it).
  final bool authenticatorRequireUnlock;

  AppSettings copyWith({
    ThemePreference? theme,
    QualityPreset? quality,
    PdfPageSize? pageSize,
    EnhancementFilter? defaultFilter,
    OcrScript? ocrScript,
    bool? autoDetectEdges,
    bool? searchablePdf,
    bool? appLock,
    int? lockAfterMinutes,
    bool? showPrivacyBanner,
    bool? hideEmptyCategories,
    bool? expiryReminders,
    bool? authenticatorRequireUnlock,
  }) => AppSettings(
    theme: theme ?? this.theme,
    quality: quality ?? this.quality,
    pageSize: pageSize ?? this.pageSize,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    ocrScript: ocrScript ?? this.ocrScript,
    autoDetectEdges: autoDetectEdges ?? this.autoDetectEdges,
    searchablePdf: searchablePdf ?? this.searchablePdf,
    appLock: appLock ?? this.appLock,
    lockAfterMinutes: lockAfterMinutes ?? this.lockAfterMinutes,
    showPrivacyBanner: showPrivacyBanner ?? this.showPrivacyBanner,
    hideEmptyCategories: hideEmptyCategories ?? this.hideEmptyCategories,
    expiryReminders: expiryReminders ?? this.expiryReminders,
    authenticatorRequireUnlock:
        authenticatorRequireUnlock ?? this.authenticatorRequireUnlock,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'quality': quality.name,
    'pageSize': pageSize.name,
    'defaultFilter': defaultFilter.name,
    'ocrScript': ocrScript.name,
    'autoDetectEdges': autoDetectEdges,
    'searchablePdf': searchablePdf,
    'appLock': appLock,
    'lockAfterMinutes': lockAfterMinutes,
    'showPrivacyBanner': showPrivacyBanner,
    'hideEmptyCategories': hideEmptyCategories,
    'expiryReminders': expiryReminders,
    'authenticatorRequireUnlock': authenticatorRequireUnlock,
  };
}
