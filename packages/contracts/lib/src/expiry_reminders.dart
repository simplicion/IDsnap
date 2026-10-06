import 'package:docscan_contracts/src/providers.dart';
import 'package:docscan_contracts/src/settings_controller.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expiry reminders across the vault (audit H-01): one place that asks for
/// the notification permission, schedules or cancels reminders for every
/// document, and turns failures into specific, actionable messages.
///
/// Used by the expiry date picker, the Settings "Expiry reminders" switch,
/// and the app at launch (which also picks up imported documents).
class ExpiryReminders {
  ExpiryReminders(this._ref);

  final Ref _ref;

  /// The wired scheduler, or null when the app wires none (feature tests,
  /// previews). The production override list is checked by
  /// apps/scanner/test/overrides_coverage_test.dart, so this never hides a
  /// missing wire in the app.
  ReminderScheduler? get _scheduler {
    try {
      return _ref.read(reminderSchedulerProvider);
    } on Object {
      return null;
    }
  }

  Future<bool> _available(ReminderScheduler? s) async =>
      s != null && (await s.capability()).available;

  /// Schedules reminders for [doc] after its expiry date changed, asking for
  /// the notification permission first (Android 13+ shows the system prompt
  /// the first time). `Ok(true)` = scheduled; `Ok(false)` = reminders are
  /// off in Settings or unsupported on this platform.
  Future<Result<bool>> scheduleFor(Document doc) async {
    final scheduler = _scheduler;
    if (!_ref.read(currentSettingsProvider).expiryReminders) {
      return const Ok(false);
    }
    if (!await _available(scheduler)) return const Ok(false);
    final permission = await scheduler!.requestPermission();
    if (permission case Err(:final failure)) return Err(failure);
    return switch (await scheduler.scheduleExpiry(doc)) {
      Ok() => const Ok(true),
      Err(:final failure) => Err(failure),
    };
  }

  /// Settings switch on: asks for permission, then schedules every document
  /// that has an expiry date. Returns how many documents have reminders.
  /// Nothing is scheduled when permission is denied.
  Future<Result<int>> enableAll() async {
    final scheduler = _scheduler;
    if (!await _available(scheduler)) {
      return const Err(
        AppFailure(
          FailureCode.offlineDependencyUnavailable,
          heading: 'Reminders unavailable',
          message: 'Expiry reminders work on Android and iPhone only.',
          action: FailureAction.none,
        ),
      );
    }
    final permission = await scheduler!.requestPermission();
    if (permission case Err(:final failure)) return Err(failure);
    return await _scheduleAll(scheduler);
  }

  /// Settings switch off: cancels every reminder.
  Future<Result<void>> disableAll() async {
    final scheduler = _scheduler;
    if (!await _available(scheduler)) return const Ok(null);
    AppFailure? first;
    for (final doc in await _documentsWithExpiry()) {
      final r = await scheduler!.cancel(doc.id);
      if (r case Err(:final failure)) first ??= failure;
    }
    return first == null ? const Ok(null) : Err(first);
  }

  /// Brings scheduled reminders in line with the setting without any
  /// prompt: at launch and after an import. Returns the number of documents
  /// with reminders (0 when off).
  Future<Result<int>> resync() async {
    final scheduler = _scheduler;
    if (!await _available(scheduler)) return const Ok(0);
    final settings = await _ref.read(settingsProvider.future);
    if (!settings.expiryReminders) {
      return switch (await disableAll()) {
        Ok() => const Ok(0),
        Err(:final failure) => Err(failure),
      };
    }
    return await _scheduleAll(scheduler!);
  }

  Future<Result<int>> _scheduleAll(ReminderScheduler scheduler) async {
    var count = 0;
    AppFailure? first;
    for (final doc in await _documentsWithExpiry()) {
      switch (await scheduler.scheduleExpiry(doc)) {
        case Ok():
          count++;
        case Err(:final failure):
          first ??= failure;
      }
    }
    return first == null ? Ok(count) : Err(first);
  }

  /// Every document with an expiry date, including those in locked folders
  /// (global queries hide locked contents; per-folder queries don't).
  Future<List<Document>> _documentsWithExpiry() async {
    final repo = _ref.read(documentRepositoryProvider);
    final byId = <String, Document>{
      for (final d in await repo.watch(const DocumentQuery()).first) d.id: d,
    };
    List<Folder> folders;
    try {
      folders = await _ref.read(folderRepositoryProvider).allFolders();
    } on Object {
      folders = const [];
    }
    for (final f in folders) {
      for (final d in await repo.watch(DocumentQuery(folderId: f.id)).first) {
        byId[d.id] = d;
      }
    }
    return [
      for (final d in byId.values)
        if (d.expiresAt != null) d,
    ];
  }
}

final expiryRemindersProvider = Provider<ExpiryReminders>(ExpiryReminders.new);
