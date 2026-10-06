/// Library feature: the ID Vault (nested user folders, optional per-folder
/// locks), the files browser and the document viewer.
library;

export 'src/document_screen.dart' show DocumentScreen;
export 'src/files_screen.dart' show FilesScreen;
export 'src/folder_screen.dart' show FolderScreen;
export 'src/folders/folder_lock.dart' show folderLockExplainer;
export 'src/folders/folder_providers.dart'
    show
        FolderAccess,
        FolderSecureSetter,
        folderAccessProvider,
        folderPinStoreProvider,
        folderSecureSetterProvider;
export 'src/library_controller.dart'
    show PendingDeleteController, pendingDeletesProvider;
export 'src/routes.dart' show libraryRoutes;
export 'src/vault.dart' show PrivacyBanner;
