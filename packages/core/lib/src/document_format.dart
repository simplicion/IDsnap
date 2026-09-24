import 'dart:typed_data';

/// File formats DocScan understands. Detected from content, never trusted
/// from the extension alone.
enum DocumentFormat {
  pdf('PDF', 'pdf', 'application/pdf'),
  jpeg('JPEG image', 'jpg', 'image/jpeg'),
  png('PNG image', 'png', 'image/png'),
  webp('WebP image', 'webp', 'image/webp'),
  heic('HEIC image', 'heic', 'image/heic'),
  gif('GIF image', 'gif', 'image/gif'),
  bmp('BMP image', 'bmp', 'image/bmp'),
  tiff('TIFF image', 'tiff', 'image/tiff'),
  docx(
    'Word document',
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  xlsx(
    'Excel workbook',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  pptx(
    'PowerPoint deck',
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  ),
  txt('Plain text', 'txt', 'text/plain'),
  markdown('Markdown', 'md', 'text/markdown'),
  html('HTML', 'html', 'text/html'),
  csv('CSV', 'csv', 'text/csv'),
  zip('ZIP archive', 'zip', 'application/zip'),
  unknown('Unknown', 'bin', 'application/octet-stream');

  const DocumentFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;

  bool get isImage => const {jpeg, png, webp, heic, gif, bmp, tiff}.contains(this);
  bool get isText => const {txt, markdown, html, csv}.contains(this);

  static DocumentFormat fromExtension(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'pdf' => pdf,
      'jpg' || 'jpeg' => jpeg,
      'png' => png,
      'webp' => webp,
      'heic' || 'heif' => heic,
      'gif' => gif,
      'bmp' => bmp,
      'tif' || 'tiff' => tiff,
      'docx' => docx,
      'xlsx' => xlsx,
      'pptx' => pptx,
      'txt' => txt,
      'md' || 'markdown' => markdown,
      'htm' || 'html' => html,
      'csv' => csv,
      'zip' => zip,
      _ => unknown,
    };
  }

  /// Sniffs magic bytes. Falls back to [nameHint]'s extension only for
  /// formats without a signature (text) or ZIP containers (OOXML).
  static DocumentFormat sniff(Uint8List head, {String? nameHint}) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (head.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (head[offset + i] != sig[i]) return false;
      }
      return true;
    }

    final hint = nameHint == null ? unknown : fromExtension(nameHint);
    if (starts([0x25, 0x50, 0x44, 0x46])) return pdf;
    if (starts([0xFF, 0xD8, 0xFF])) return jpeg;
    if (starts([0x89, 0x50, 0x4E, 0x47])) return png;
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return webp;
    }
    if (starts([0x66, 0x74, 0x79, 0x70], 4) && head.length >= 12) {
      final brand = String.fromCharCodes(head.sublist(8, 12));
      if (brand.startsWith('hei') ||
          brand.startsWith('mif') ||
          brand == 'msf1') {
        return heic;
      }
    }
    if (starts([0x47, 0x49, 0x46, 0x38])) return gif;
    if (starts([0x42, 0x4D])) return bmp;
    if (starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A])) {
      return tiff;
    }
    if (starts([0x50, 0x4B, 0x03, 0x04])) {
      return const {docx, xlsx, pptx}.contains(hint) ? hint : zip;
    }
    if (hint.isText && _looksLikeText(head)) return hint;
    if (hint == unknown && head.isNotEmpty && _looksLikeText(head)) return txt;
    return unknown;
  }

  static bool _looksLikeText(Uint8List head) {
    if (head.isEmpty) return true;
    var control = 0;
    for (final b in head) {
      if (b == 0) return false;
      if (b < 0x09 || (b > 0x0D && b < 0x20)) control++;
    }
    return control / head.length < 0.05;
  }
}
