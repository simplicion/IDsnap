import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/entities/folder.dart';
import 'package:docscan_domain/src/ports/document_repository.dart';
import 'package:meta/meta.dart';

/// Nested, user-created folders. Implemented by the data layer next to
/// [DocumentRepository]; kept as a separate port so existing fakes of
/// [DocumentRepository] don't have to change.
abstract interface class FolderRepository {
  /// Every folder, flat (build a [FolderTree] for structure).
  Stream<List<Folder>> watchAllFolders();

  Future<List<Folder>> allFolders();

  /// Creates a folder under [parentId] (`null` = top level). The name is
  /// validated with [FolderNames.validate] against its siblings.
  Future<Result<Folder>> createFolder({
    required String name,
    String? parentId,
    String? templateKey,
    String? icon,
    String? color,
  });

  /// Renames with the same validation as [createFolder].
  Future<Result<void>> renameFolder(String id, String name);

  Future<Result<void>> setFolderStyle(
    String id, {
    required String? icon,
    required String? color,
  });

  Future<Result<void>> setFolderLockMode(String id, FolderLockMode mode);

  /// Moves [id] under [newParentId] (`null` = top level). Refuses to move a
  /// folder into itself or one of its subfolders, and name clashes.
  Future<Result<void>> moveFolder(String id, String? newParentId);

  /// Deletes [id]. Returns the documents whose rows were removed (only with
  /// [FolderDeleteMode.deleteContents]) so the caller can delete their files.
  Future<Result<List<Document>>> deleteFolder(String id, FolderDeleteMode mode);

  /// Subfolders and files directly inside [folderId] (`null` = top level;
  /// top-level files also include any whose folder no longer exists).
  Stream<FolderContents> watchContents(
    String? folderId, {
    DocumentSort sort = DocumentSort.newest,
    DocumentFilter filter = DocumentFilter.all,
  });

  /// Documents directly inside each folder (`null` key = top level).
  Stream<Map<String?, int>> watchDirectCounts();

  /// Top level → [folderId] inclusive.
  Future<List<Folder>> breadcrumb(String folderId);

  /// Name search across [FolderSearch.withinFolderId]'s subtree (whole vault
  /// when `null`). Documents inside locked folders are excluded unless the locked
  /// folder is in [FolderSearch.unlockedFolderIds].
  Stream<List<Document>> watchSearch(FolderSearch query);

  /// Moves documents into [folderId] (`null` = top level).
  Future<Result<void>> moveDocuments(
    List<String> documentIds,
    String? folderId,
  );
}

@immutable
class FolderSearch {
  const FolderSearch({
    required this.text,
    this.withinFolderId,
    this.unlockedFolderIds = const {},
    this.sort = DocumentSort.newest,
    this.filter = DocumentFilter.all,
  });

  final String text;
  final String? withinFolderId;
  final Set<String> unlockedFolderIds;
  final DocumentSort sort;
  final DocumentFilter filter;

  @override
  bool operator ==(Object other) =>
      other is FolderSearch &&
      other.text == text &&
      other.withinFolderId == withinFolderId &&
      other.sort == sort &&
      other.filter == filter &&
      other.unlockedFolderIds.length == unlockedFolderIds.length &&
      other.unlockedFolderIds.containsAll(unlockedFolderIds);

  @override
  int get hashCode => Object.hash(
    text,
    withinFolderId,
    sort,
    filter,
    Object.hashAllUnordered(unlockedFolderIds),
  );
}

/// Result of checking a folder PIN.
sealed class PinCheck {
  const PinCheck();
}

final class PinAccepted extends PinCheck {
  const PinAccepted();
}

/// Wrong PIN. [attemptsLeft] = tries before a delay starts (0 when the next
/// wrong PIN will be delayed); [retryAfter] is set when a delay now applies.
final class PinRejected extends PinCheck {
  const PinRejected({required this.attemptsLeft, this.retryAfter});

  final int attemptsLeft;
  final Duration? retryAfter;
}

/// Too many wrong PINs: nothing was checked; try again after [retryAfter].
final class PinThrottled extends PinCheck {
  const PinThrottled(this.retryAfter);

  final Duration retryAfter;
}

/// Per-folder PINs. Implementations store only a salted, slow hash in the
/// platform keystore (never in SQLite) and throttle repeated failures.
abstract interface class FolderPinStore {
  static final _valid = RegExp(r'^\d{4,8}$');

  /// 4–8 digits.
  static bool isValidPin(String pin) => _valid.hasMatch(pin);

  Future<bool> hasPin(String folderId);

  /// Replaces any PIN for [folderId] and resets its failure counter.
  Future<Result<void>> setPin(String folderId, String pin);

  Future<Result<PinCheck>> verifyPin(String folderId, String pin);

  /// Remaining delay before another attempt is allowed, if any.
  Future<Duration?> retryAfter(String folderId);

  Future<void> removePin(String folderId);
}
