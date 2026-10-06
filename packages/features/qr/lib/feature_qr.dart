/// Offline QR & barcode tool: continuous camera scanning (torch, every
/// common symbology), decoding pictures, typed results with local actions,
/// link-safety warnings, a QR generator with PNG export and an optional
/// local scan history. Nothing is uploaded; links are only handed to other
/// apps when the user taps "Open".
library;

export 'src/generate_screen.dart'
    show QrGenerateScreen, QrGenerateType, qrExportSizes;
export 'src/history.dart'
    show
        JsonFileQrHistoryStore,
        MemoryQrHistoryStore,
        QrHistoryController,
        QrHistoryEntry,
        QrHistoryState,
        QrHistoryStore,
        qrHistoryProvider,
        qrHistoryStoreProvider;
export 'src/history_backup.dart' show QrHistoryBackupSection;
export 'src/history_screen.dart' show QrHistoryScreen;
export 'src/result_screen.dart' show CodeResultScreen;
export 'src/routes.dart' show qrRoutes, qrToolPath;
export 'src/scan_screen.dart' show CodeListScreen, QrScanScreen;
export 'src/services.dart'
    show
        CodeScanner,
        CodeScannerController,
        PlatformQrActions,
        QrActions,
        UnavailableCodeScanner,
        codeScannerProvider,
        qrActionsProvider,
        useAppleMapsProvider;
export 'src/widgets.dart' show QrMatrixView, kindIcon;
