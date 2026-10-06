/// Offline 2FA authenticator: TOTP/HOTP codes with countdown rings, a
/// biometric reveal gate, QR/manual setup and emergency recovery codes.
/// Secrets stay in the platform keystore; nothing uses the network.
library;

export 'src/account_screen.dart' show AccountScreen;
export 'src/add_account_screen.dart' show AddAccountScreen;
export 'src/authenticator_screen.dart' show AuthenticatorScreen;
export 'src/routes.dart' show authenticatorRoutes;
export 'src/scan_qr_screen.dart' show ScanQrScreen;
export 'src/services.dart'
    show
        ClipboardAccess,
        QrScanner,
        SecureClipboard,
        SecureFlagSetter,
        SystemClipboardAccess,
        UnavailableQrScanner,
        authenticatorClockProvider,
        clipboardAccessProvider,
        groupCode,
        qrScannerProvider,
        revealProvider,
        secureClipboardProvider,
        secureFlagSetterProvider;
export 'src/widgets.dart' show CountdownRing, RingPainter, remainingInStep;
