import 'package:docscan_contracts/src/entitlements.dart';

/// Navigation contract. Features navigate only through these paths so no
/// feature imports another feature.
abstract final class Routes {
  // Shell tabs.
  static const home = '/';
  static const files = '/files';
  static const tools = '/tools';

  /// Offline 2FA authenticator tab (feature_authenticator).
  static const authenticator = '/authenticator';

  /// Full-screen settings, pushed over the shell (no longer a tab).
  static const settings = '/settings';

  // Authenticator sub-pages (feature_authenticator), pushed over the shell.
  static const authenticatorAdd = '/authenticator/add';
  static const authenticatorScan = '/authenticator/scan';
  static String authenticatorAccount(String id) => '/authenticator/account/$id';

  // Scan flow (feature_scan).
  /// Starts or resumes a scan. [source] is `camera` or `gallery`.
  /// [folderId] saves the result into that ID Vault folder by default.
  static String scan({
    ScanSource source = ScanSource.camera,
    String? slot,
    String? folderId,
  }) =>
      '/scan?source=${source.name}${slot == null ? '' : '&slot=$slot'}'
      '${folderId == null ? '' : '&folder=$folderId'}';

  /// ID card front & back on one page (roadmap A). [slot] = VaultSlot.key
  /// (legacy, unused). [folderId] saves into that ID Vault folder by default.
  static String idCard({String? slot, String? folderId}) {
    final query = {'slot': ?slot, 'folder': ?folderId};
    return Uri(
      path: '/scan/id-card',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// Passport-size photo camera: live face checks, auto-capture, crop to a
  /// size preset, save as JPEG or print sheet.
  static const passportPhotoCamera = '/scan/passport-photo';

  /// [passportPhotoCamera]; [folderId] saves into that folder by default.
  static String passportPhoto({String? folderId}) => folderId == null
      ? passportPhotoCamera
      : '$passportPhotoCamera?folder=$folderId';
  static const scanReview = '/scan/review';
  static String scanCrop(String pageId) => '/scan/crop/$pageId';
  static const scanSave = '/scan/save';

  // Library (feature_library).
  static String document(String id) => '/files/doc/$id';
  static String folder(String id) => '/files/folder/$id';

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

  // Secure notes (feature_notes), pushed over the shell.
  static const notes = '/notes';
  static String note(String id) => '/notes/$id';

  // IDSnap Pro (feature_paywall; docs/adr/0009). Prefer ensurePro() over
  // pushing the paywall directly.
  /// Paywall. [feature] tailors the headline; [from] is where to continue
  /// after a purchase (set by the router backstop).
  static String paywall({ProFeature? feature, String? from}) {
    final query = {'feature': ?feature?.name, 'from': ?from};
    return Uri(
      path: '/paywall',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// Settings › Subscription: plan, renewal, manage, restore.
  static const subscription = '/subscription';

  /// Subscription terms (a local screen; no web links).
  static const subscriptionTerms = '/subscription/terms';

  // Application kits (feature_tools, roadmap C).
  static const kits = '/tools/kits';
  static String kit(String id) => '/tools/kits/$id';

  // QR & barcode tool (feature_qr).
  static const qrScanner = '/tools/qr';
  static const qrGenerate = '/tools/qr/generate';
  static const qrHistory = '/tools/qr/history';
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
  convert('convert'),

  /// Sign a PDF with a saved or new signature (PRD 3.3).
  signPdf('sign-pdf'),

  /// Create and manage saved signatures (PRD 3.3).
  mySignature('my-signature'),

  /// Password-protect files: AES-256 PDF or AES-256 ZIP.
  protectFile('protect-file'),

  /// Remove a known password from a PDF.
  removePdfPassword('remove-pdf-password');

  const ToolId(this.path);
  final String path;
}
