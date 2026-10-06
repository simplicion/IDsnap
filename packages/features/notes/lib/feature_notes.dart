/// Encrypted secure notes: templates (Wi-Fi, bank account, card PIN hint,
/// recovery info, licence keys), checklists, pinning, per-note locks
/// (device or PIN), FLAG_SECURE and a 60 s clipboard clear. Notes live in
/// the SQLCipher database (ADR-0010).
library;

export 'src/note_editor_screen.dart' show NoteEditorScreen;
export 'src/note_lock.dart' show noteLockExplainer;
export 'src/notes_screen.dart' show NotesScreen, createNote;
export 'src/providers.dart'
    show
        notePinKey,
        notePinStoreProvider,
        notesClipboardAccessProvider,
        notesSecureSetterProvider,
        unlockedNotesProvider;
export 'src/routes.dart' show notesRoutes;
