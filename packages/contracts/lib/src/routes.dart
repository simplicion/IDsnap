/// Navigation contract. Features navigate only through these paths so no
/// feature imports another feature.
abstract final class Routes {
  // Shell tabs.
  static const home = '/';
  static const files = '/files';
  static const tools = '/tools';
  static const settings = '/settings';

  // Scan flow (feature_scan).
  /// Starts or resumes a scan. [source] is `camera` or `gallery`.
  static String scan({ScanSource source = ScanSource.camera, String? slot}) =>
      '/scan?source=${source.name}${slot == null ? '' : '&slot=$slot'}';

  /// ID card front & back on one page (roadmap A). [slot] = VaultSlot.key.
  static String idCard({String? slot}) =>
      '/scan/id-card${slot == null ? '' : '?slot=$slot'}';
  static const scanReview = '/scan/review';
  static String scanCrop(String pageId) => '/scan/crop/$pageId';
  static const scanSave = '/scan/save';

  // Library (feature_library).
  static String document(String id) => '/files/doc/$id';
  static String folder(String id) => '/files/folder/$id';

  /// Vault category page (roadmap B1). [category] = DocumentCategory.name.
  static String category(String category) => '/files/category/$category';

  // Tools (feature_tools). [docId] preselects a library document.
  static String tool(ToolId tool, {String? docId}) =>
      '/tools/${tool.path}${docId == null ? '' : '?doc=$docId'}';
  static String convert(String specId, {String? docId}) =>
      '/tools/convert/$specId${docId == null ? '' : '?doc=$docId'}';

  // Settings sub-pages (feature_settings).
  static const privacy = '/settings/privacy';
  static const about = '/settings/about';
  static const security = '/settings/security';
  static const dataExport = '/settings/data';

  // Application kits (feature_tools, roadmap C).
  static const kits = '/tools/kits';
  static String kit(String id) => '/tools/kits/$id';
}

enum ScanSource { camera, gallery, resume }

/// Every tool screen, with its route segment.
enum ToolId {
  ocr('ocr'),
  imagesToPdf('images-to-pdf'),
  merge('merge'),
  split('split'),
  organize('organize'),
  compressPdf('compress-pdf'),
  pdfToImages('pdf-to-images'),
  compressImage('compress-image'),
  photoCrop('photo-crop'),
  resizeImage('resize-image'),
  kits('kits'),
  convert('convert');

  const ToolId(this.path);
  final String path;
}
