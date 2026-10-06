import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_notes/src/note_lock.dart';
import 'package:feature_notes/src/notes_screen.dart';
import 'package:feature_notes/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _noteProvider = FutureProvider.autoDispose.family<Note?, String>(
  (ref, id) => ref.watch(notesRepositoryProvider).byId(id),
);

/// Opens note [noteId]: unlock gate for locked notes, then the editor.
class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({required this.noteId, super.key});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(_noteProvider(noteId));
    final unlocked = ref.watch(unlockedNotesProvider).contains(noteId);
    return NotesSecureScope(
      child: switch (note) {
        AsyncData(value: null) => Scaffold(
          appBar: AppBar(),
          body: const FailureView(AppFailure(FailureCode.notFound)),
        ),
        AsyncData(:final value?) when value.isLocked && !unlocked => Scaffold(
          appBar: AppBar(),
          body: EmptyState(
            icon: Icons.lock_rounded,
            title: 'This note is locked',
            message: noteLockExplainer,
            actionLabel: 'Unlock',
            onAction: () => unlockNote(context, ref, value),
          ),
        ),
        AsyncData(:final value?) => _Editor(note: value),
        AsyncError(:final error) => Scaffold(
          appBar: AppBar(),
          body: FailureView(
            error is AppFailure
                ? error
                : const AppFailure(
                    FailureCode.unknown,
                    heading: "This note couldn't be opened",
                    message:
                        'It is still saved on this phone. Go back and open '
                        'it again, or restart IDSnap.',
                    action: FailureAction.none,
                  ),
          ),
        ),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.note});

  final Note note;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  static const autosaveDelay = Duration(milliseconds: 800);

  late final TextEditingController _title = TextEditingController(
    text: widget.note.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.note.body,
  );
  late final TextEditingController _tag = TextEditingController(
    text: widget.note.tag ?? '',
  );
  late final NotesRepository _repo = ref.read(notesRepositoryProvider);
  late Note _note = widget.note;
  Timer? _debounce;
  bool _dirty = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _tag]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    final t = _tag.text.trim();
    final next = _note.copyWith(
      title: _title.text,
      body: _body.text,
      tag: t.isEmpty ? null : t,
      clearTag: t.isEmpty,
    );
    if (next == _note) return;
    _note = next;
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, () => unawaited(_save()));
    setState(() {}); // Checklist view follows the body.
  }

  Future<void> _save() async {
    _debounce?.cancel();
    if (!_dirty || _deleted) return;
    _dirty = false;
    final r = await _repo.save(_note);
    if (r case Err(:final failure) when mounted) {
      showFailureSnack(context, failure);
    }
  }

  @override
  void dispose() {
    // Autosave on leave; the repository outlives this screen.
    unawaited(_save());
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = [
      if (_note.title.trim().isNotEmpty) _note.title.trim(),
      _note.body.trim(),
    ].join('\n');
    await ref.read(notesClipboardProvider).copy(text);
    if (!mounted) return;
    showAppSnack(
      context,
      'Copied. The clipboard clears in '
      '${SecureClipboard.defaultClearAfter.inSeconds} seconds.',
    );
  }

  Future<void> _togglePin() async {
    await _repo.setPinned(_note.id, pinned: !_note.pinned);
    setState(() => _note = _note.copyWith(pinned: !_note.pinned));
  }

  Future<void> _lock() async {
    await _save();
    if (!mounted) return;
    final mode = await chooseNoteLock(context, ref, _note);
    if (mode == null || !mounted) return;
    final r = await _repo.setLockMode(_note.id, mode);
    if (!mounted) return;
    r.fold((_) {
      setState(() => _note = _note.copyWith(lockMode: mode));
      if (mode != FolderLockMode.none) {
        ref.read(unlockedNotesProvider.notifier).add(_note.id);
      }
      showAppSnack(
        context,
        mode == FolderLockMode.none ? 'Lock removed' : 'Note locked',
      );
    }, (f) => showFailureSnack(context, f));
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Delete this note?',
      message: "It's removed from this phone. This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _deleted = true;
    _debounce?.cancel();
    final r = await _repo.delete(_note.id);
    if (!mounted) return;
    if (r case Err(:final failure)) {
      _deleted = false;
      showFailureSnack(context, failure);
      return;
    }
    await ref
        .read(notePinStoreProvider)
        .removePin(notePinKey(_note.id))
        .catchError((Object _) {});
    if (!mounted) return;
    showAppSnack(context, 'Note deleted');
    context.pop();
  }

  void _toggleItem(int line) {
    _body.text = ChecklistLine.toggle(_body.text, line);
  }

  void _addItem() {
    final text = _body.text;
    final sep = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    _body
      ..text = '$text$sep- [ ] '
      ..selection = TextSelection.collapsed(offset: _body.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _note.body.split('\n');
    final items = [
      for (final (i, l) in lines.indexed)
        if (ChecklistLine.parse(l) case final item?) (i, item),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_note.template.label),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: _note.pinned ? 'Unpin' : 'Pin',
            icon: Icon(
              _note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            ),
            onPressed: _togglePin,
          ),
          IconButton(
            tooltip: _note.isLocked ? 'Change lock' : 'Lock',
            icon: Icon(
              _note.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            ),
            onPressed: _lock,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      body: PopScope(
        onPopInvokedWithResult: (_, _) => unawaited(_save()),
        child: ListView(
          padding: const EdgeInsets.all(Space.gutter),
          children: [
            TextField(
              key: const Key('note-title'),
              controller: _title,
              style: context.text.titleLarge,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
            ),
            TextField(
              key: const Key('note-tag'),
              controller: _tag,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.sell_outlined),
                hintText: 'Tag (optional), e.g. Home, Finance',
                border: InputBorder.none,
              ),
            ),
            const Divider(),
            TextField(
              key: const Key('note-body'),
              controller: _body,
              minLines: 8,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              // Keep secrets out of keyboard learning and suggestions.
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(
                hintText:
                    'Write here. Start a line with "- [ ] " for a '
                    'checklist item.',
                border: InputBorder.none,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.checklist_rounded),
                label: const Text('Add checklist item'),
              ),
            ),
            if (items.isNotEmpty)
              Card(
                child: Column(
                  children: [
                    for (final (line, item) in items)
                      CheckboxListTile(
                        value: item.checked,
                        title: Text(item.text.isEmpty ? '…' : item.text),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (_) => _toggleItem(line),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Space.x4),
            Text(
              'Saved automatically · encrypted on this phone',
              style: context.text.bodySmall?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
