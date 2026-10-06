/// The concrete next step the UI offers for a failure (production audit
/// 2026-09: every error must say why it failed and what to do next).
enum FailureAction {
  retry('Try again'),
  pickDifferentFile('Choose another file'),
  runOcr('Extract text (OCR)'),
  openSettings('Open settings'),
  freeStorage('Free up space'),
  useFewerPages('Use fewer pages'),
  lowerQuality('Use a lower quality'),
  adjustCorners('Adjust corners'),
  changeLanguage('Change language'),

  /// Opens an email draft to support with the failure code and app version
  /// (never document contents). The app configures the address.
  contactSupport('Contact support'),
  none('');

  const FailureAction(this.label);
  final String label;
}

/// Typed failure categories (DESIGN.md, error model). Each maps to a
/// user-facing title, a plain-language recovery hint and a next action.
/// Diagnostics carry the code only — never content, names or paths.
enum FailureCode {
  permissionDenied(
    'Permission needed',
    'Allow access in Settings and try again.',
    FailureAction.openSettings,
  ),
  cameraUnavailable(
    'Camera unavailable',
    'Close other camera apps or restart the device.',
    FailureAction.retry,
  ),
  captureCancelled(
    'Scan cancelled',
    'Start a new scan when you are ready.',
    FailureAction.none,
  ),
  documentNotDetected(
    'No page found',
    'Adjust the corners manually.',
    FailureAction.adjustCorners,
  ),
  lowImageQuality(
    'Image quality is low',
    'Retake the photo in better light.',
    FailureAction.retry,
  ),
  unsupportedFormat(
    'Format not supported',
    'Choose a PDF, JPG, PNG or text file. HEIC photos: export as JPG first.',
    FailureAction.pickDifferentFile,
  ),
  corruptFile(
    'File could not be read',
    'The file may be damaged or incomplete. Try another copy.',
    FailureAction.pickDifferentFile,
  ),
  passwordProtected(
    'File is password protected',
    'Enter its password when asked, or remove it first with the Remove PDF '
        'password tool.',
    FailureAction.pickDifferentFile,
  ),
  wrongPassword(
    'Incorrect password',
    'Passwords are case-sensitive. Check Caps Lock and try again.',
    FailureAction.retry,
  ),
  modelUnavailable(
    'Text recognition unavailable',
    'This language is not installed on this device. Choose another language.',
    FailureAction.changeLanguage,
  ),
  offlineDependencyUnavailable(
    'Component not available offline',
    'Connect once to install it, then it works offline.',
    FailureAction.retry,
  ),
  insufficientStorage(
    'Not enough storage',
    'Free up space on your phone and try again.',
    FailureAction.freeStorage,
  ),
  memoryLimitExceeded(
    'File too large to process',
    'Try fewer pages or a lower quality setting.',
    FailureAction.useFewerPages,
  ),
  processingCancelled('Cancelled', 'Nothing was changed.', FailureAction.none),
  conversionFailed(
    'Conversion failed',
    'Your original file was not changed.',
    FailureAction.retry,
  ),
  outputValidationFailed(
    'Output could not be verified',
    'Nothing was saved. Please try again.',
    FailureAction.retry,
  ),
  notFound(
    'File not found',
    'It may have been moved or deleted. Choose it again.',
    FailureAction.pickDifferentFile,
  ),
  emptyFile(
    'The file is empty',
    'This file has 0 bytes. Choose the original file again.',
    FailureAction.pickDifferentFile,
  ),
  noTextFound(
    'No text found',
    'We could not find readable text. Try a sharper photo with good light.',
    FailureAction.pickDifferentFile,
  ),
  scannedPdfNeedsOcr(
    'This PDF is scanned',
    'Its pages are images without a text layer. Use Extract text (OCR) '
        'to read them.',
    FailureAction.runOcr,
  ),
  timeout(
    'This is taking too long',
    'The file may be very large. Try fewer pages or a smaller file.',
    FailureAction.useFewerPages,
  ),
  targetSizeUnreachable(
    'Size limit not reachable',
    'We could not get under the size limit without making it unreadable.',
    FailureAction.useFewerPages,
  ),
  // Authenticator (PRD Module 2).
  invalidSecretKey(
    'Secret key is not valid',
    'Check the key: it uses the letters A–Z and the digits 2–7. Spaces are '
        'fine.',
    FailureAction.none,
  ),
  invalidOtpUri(
    'Not an authenticator QR code',
    'Scan the QR code the website shows when you turn on two-step '
        'verification, or enter the key manually.',
    FailureAction.retry,
  ),
  secretUnavailable(
    'Secret key could not be read',
    "This account's key is missing from secure storage on this phone. "
        'Remove the account and add it again from the website.',
    FailureAction.none,
  ),

  /// Last resort: callers should pass a specific [AppFailure.heading] and
  /// [AppFailure.message] that say what was (not) changed and what to do
  /// (production audit M-04). This copy is only the fallback.
  unknown(
    'Something went wrong',
    'Try again. If it keeps happening, tap Contact support: we receive the '
        'error code only, never your documents.',
    FailureAction.retry,
  );

  const FailureCode(this.title, this.recovery, this.action);

  final String title;
  final String recovery;

  /// Default next step shown as the primary button.
  final FailureAction action;
}

/// A failure that is safe to log: [cause] is kept for debugging but is never
/// included in [toString] because it may contain paths or document content.
class AppFailure implements Exception {
  const AppFailure(
    this.code, {
    this.detail,
    this.cause,
    this.stackTrace,
    this.action,
    this.message,
    this.heading,
  });

  final FailureCode code;

  /// Optional specific title replacing [FailureCode.title] (e.g. "Reminder
  /// not set" instead of the generic "Something went wrong").
  final String? heading;

  /// Optional non-sensitive detail for UI (e.g. "Page 3").
  final String? detail;

  /// Optional specific explanation replacing [FailureCode.recovery].
  final String? message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Overrides [FailureCode.action] when a more specific step applies.
  final FailureAction? action;

  String get title => heading ?? code.title;
  String get recovery => message ?? code.recovery;
  FailureAction get nextAction => action ?? code.action;

  /// Redacted diagnostics safe to copy into a support message: failure code,
  /// cause type and a scrubbed cause message (paths and long text removed).
  String get diagnostics {
    final type = cause?.runtimeType.toString() ?? 'none';
    final raw = cause?.toString() ?? '';
    final scrubbed = raw
        .replaceAll(RegExp(r'([A-Za-z]:)?[\\/][^\s,:)]+'), '<path>')
        .replaceAll(RegExp(r'\s+'), ' ');
    final short = scrubbed.length > 160
        ? '${scrubbed.substring(0, 160)}…'
        : scrubbed;
    return 'code=${code.name} cause=$type ${short.isEmpty ? '' : 'msg=$short'}'
        .trim();
  }

  AppFailure withDetail(String detail) => AppFailure(
    code,
    detail: detail,
    cause: cause,
    stackTrace: stackTrace,
    action: action,
    message: message,
    heading: heading,
  );

  @override
  String toString() => 'AppFailure(${code.name})';
}
