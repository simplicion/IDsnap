import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_notes/src/note_lock.dart';
import 'package:feature_notes/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Keeps FLAG_SECURE on (no screenshots, blank app-switcher thumbnail)
/// while [child] is on screen. Follows [TickerMode], so covered routes and
/// inactive tabs drop the flag.
class NotesSecureScope extends ConsumerStatefulWidget {
  const NotesSecureScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotesSecureScope> createState() => _NotesSecureScopeState();
}

class _NotesSecureScopeState extends ConsumerState<NotesSecureScope> {
  NotesSecureFlag? _flag;
  bool _holding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flag ??= ref.read(notesSecureFlagProvider);
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _holding) return;
    _holding = active;
    active ? _flag!.acquire() : _flag!.release();
  }

  @override
  void dispose() {
    if (_holding) _flag!.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Creates a note from a template picked in a bottom sheet and opens it.
///
/// Creating notes is a Pro feature after the trial; reading, searching and
/// editing existing notes stays free (the user's data is never locked in).
Future<void> createNote(BuildContext context, WidgetRef ref) async {
  if (!await ensurePro(context, ref, ProFeature.secureNotes)) return;
  if (!context.mounted) return;
  final template = await showModalBottomSheet<NoteTemplate>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text('New secure note', style: context.text.titleMedium),
          ),
          for (final t in NoteTemplate.values)
            ListTile(
              leading: Icon(noteTemplateIcon(t)),
              title: Text(t.label),
              onTap: () => Navigator.pop(context, t),
            ),
        ],
      ),
    ),
  );
  if (template == null || !context.mounted) return;
  final created = await ref
      .read(notesRepositoryProvider)
      .create(
        title: template == NoteTemplate.custom ? '' : template.label,
        body: template.body,
        template: template,
      );
  if (!context.mounted) return;
  switch (created) {
    case Ok(:final value):
      unawaited(context.push(Routes.note(value.id)));
    case Err(:final failure):
      showFailureSnack(context, failure);
  }
}

IconData noteTemplateIcon(NoteTemplate t) => switch (t) {
  NoteTemplate.custom => Icons.sticky_note_2_outlined,
  NoteTemplate.wifi => Icons.wifi_rounded,
  NoteTemplate.bankAccount => Icons.account_balance_outlined,
  NoteTemplate.cardPin => Icons.credit_card_rounded,
  NoteTemplate.recovery => Icons.key_rounded,
  NoteTemplate.licence => Icons.confirmation_number_outlined,
};

/// Secure notes: list, search, pin and create.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  late final UnlockedNotes _unlocked;

  @override
  void initState() {
    super.initState();
    _unlocked = ref.read(unlockedNotesProvider.notifier);
    // Leaving the app relocks every note.
    _lifecycle = AppLifecycleListener(onHide: _unlocked.clear);
    _search.text = ref.read(notesSearchProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    // Leaving the notes relocks them too.
    scheduleMicrotask(_unlocked.clear);
    super.dispose();
  }

  Future<void> _open(Note note) async {
    if (!await unlockNote(context, ref, note) || !mounted) return;
    unawaited(context.push(Routes.note(note.id)));
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesListProvider);
    final searching = ref.watch(notesSearchProvider).trim().isNotEmpty;
    return NotesSecureScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Secure notes')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => createNote(context, ref),
          icon: const Icon(Icons.add_rounded),
          // Creating notes is Pro; reading and editing stay free.
          label: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New note'),
              SizedBox(width: Space.x2),
              ProBadge(ProFeature.secureNotes),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.x2,
                Space.gutter,
                Space.x2,
              ),
              child: TextField(
                key: const Key('notes-search'),
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search notes',
                ),
                onChanged: ref.read(notesSearchProvider.notifier).set,
              ),
            ),
            Expanded(
              child: switch (notes) {
                AsyncData(:final value) when value.isEmpty => EmptyState(
                  icon: searching
                      ? Icons.search_off_rounded
                      : Icons.sticky_note_2_outlined,
                  title: searching ? 'No matching notes' : 'No notes yet',
                  message: searching
                      ? 'Locked notes are never searched. Open them from the '
                            'list instead.'
                      : 'Keep Wi-Fi passwords, account details, recovery '
                            'codes and licence keys here. Notes are '
                            'encrypted on this phone.',
                ),
                AsyncData(:final value) => ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: value.length,
                  itemBuilder: (context, i) =>
                      _NoteTile(note: value[i], onTap: () => _open(value[i])),
                ),
                AsyncError(:final error) => FailureView(
                  error is AppFailure
                      ? error
                      : const AppFailure(
                          FailureCode.unknown,
                          heading: "Your notes couldn't be loaded",
                          message:
                              'They are still saved on this phone. Go back '
                              'and open Notes again, or restart IDSnap.',
                          action: FailureAction.none,
                        ),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = note.preview; // Empty for locked notes.
    return ListTile(
      onTap: onTap,
      leading: IconBadge(
        note.isLocked ? Icons.lock_rounded : noteTemplateIcon(note.template),
        size: 40,
      ),
      title: Text(
        note.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (note.isLocked) 'Locked' else if (preview.isNotEmpty) preview,
          ?note.tag,
          formatRelativeDate(note.updatedAt),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: note.pinned ? 'Unpin' : 'Pin',
        icon: Icon(
          note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        ),
        onPressed: () => ref
            .read(notesRepositoryProvider)
            .setPinned(note.id, pinned: !note.pinned),
      ),
    );
  }
}
