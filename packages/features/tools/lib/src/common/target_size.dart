import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/kits/models.dart' show formatLimit;

/// Common upload caps for PDFs, in bytes.
const pdfTargetPresets = <int>[
  100 * 1024,
  200 * 1024,
  300 * 1024,
  500 * 1024,
  1024 * 1024,
  2 * 1024 * 1024,
];

/// The limit can't be met without making the document unreadable.
AppFailure pdfTargetUnreachable(int maxBytes) => AppFailure(
  FailureCode.targetSizeUnreachable,
  detail: 'Limit ${formatLimit(maxBytes)}',
  message:
      "Can't reach ${formatLimit(maxBytes)} without making text unreadable. "
      'Try fewer pages.',
);

/// Failures a stronger level can't fix (the file itself is the problem).
const _fatal = {
  FailureCode.passwordProtected,
  FailureCode.corruptFile,
  FailureCode.notFound,
  FailureCode.emptyFile,
  FailureCode.insufficientStorage,
};

/// Compresses [path] with each [PdfCompressionLevel] in turn — every step
/// renders at a lower DPI and JPEG quality — and returns the first result
/// at or under [maxBytes]. `Err(targetSizeUnreachable)` when even the
/// strongest level is too big. Shared by Compress PDF and application kits.
///
/// [onStep] receives the fraction of levels tried (0–1).
Future<Result<({Uint8List bytes, PdfCompressionLevel level})>>
compressPdfToTarget(
  PdfEngine pdf,
  String path,
  int maxBytes, {
  void Function(double fraction)? onStep,
}) async {
  const levels = PdfCompressionLevel.values;
  for (final (i, level) in levels.indexed) {
    final r = await pdf.compress(path, level);
    onStep?.call((i + 1) / levels.length);
    switch (r) {
      case Err(:final failure) when _fatal.contains(failure.code):
        return Err(failure);
      case Ok(value: final bytes) when bytes.length <= maxBytes:
        return Ok((bytes: bytes, level: level));
      case _:
        continue;
    }
  }
  return Err(pdfTargetUnreachable(maxBytes));
}
