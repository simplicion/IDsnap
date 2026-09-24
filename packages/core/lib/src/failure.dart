/// Typed failure categories (DESIGN.md, error model). Each maps to a
/// user-facing message and a recovery hint; diagnostics carry the code only.
enum FailureCode {
  permissionDenied('Permission needed', 'Allow access in Settings and try again.'),
  cameraUnavailable('Camera unavailable', 'Close other camera apps or restart the device.'),
  captureCancelled('Scan cancelled', 'Start a new scan when you are ready.'),
  documentNotDetected('No page found', 'Adjust the corners manually.'),
  lowImageQuality('Image quality is low', 'Retake the photo in better light.'),
  unsupportedFormat('Format not supported', 'Choose a PDF, image, or text file.'),
  corruptFile('File could not be read', 'The file may be damaged. Try another copy.'),
  passwordProtected('File is password protected', 'Remove the password in the source app first.'),
  modelUnavailable('Recognition model unavailable', 'This language is not installed on this device.'),
  offlineDependencyUnavailable('Component not available offline', 'Connect once to install it, then it works offline.'),
  insufficientStorage('Not enough storage', 'Free up space and try again.'),
  memoryLimitExceeded('File too large to process', 'Try fewer pages or a lower quality preset.'),
  processingCancelled('Cancelled', 'Nothing was changed.'),
  conversionFailed('Conversion failed', 'Your original file was not changed.'),
  outputValidationFailed('Output could not be verified', 'Nothing was saved. Please try again.'),
  notFound('Not found', 'The item may have been deleted.'),
  unknown('Something went wrong', 'Please try again.');

  const FailureCode(this.title, this.recovery);

  final String title;
  final String recovery;
}

/// A failure that is safe to log: [cause] is kept for debugging but is never
/// included in [toString] because it may contain paths or document content.
class AppFailure implements Exception {
  const AppFailure(this.code, {this.detail, this.cause, this.stackTrace});

  final FailureCode code;

  /// Optional non-sensitive detail for UI (e.g. "Page 3").
  final String? detail;
  final Object? cause;
  final StackTrace? stackTrace;

  String get title => code.title;
  String get recovery => code.recovery;

  @override
  String toString() => 'AppFailure(${code.name})';
}
