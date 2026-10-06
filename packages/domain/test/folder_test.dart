import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

Folder _f(
  String id, {
  String? parent,
  FolderLockMode lock = FolderLockMode.none,
  String? name,
}) => Folder(
  id: id,
  name: name ?? id,
  parentId: parent,
  lockMode: lock,
  createdAt: DateTime(2026),
);

void main() {
  group('FolderTree', () {
    final tree = FolderTree([
      _f('a', name: 'Alpha'),
      _f('b', parent: 'a', name: 'beta'),
      _f('c', parent: 'b', lock: FolderLockMode.pin),
      _f('d', parent: 'c'),
      _f('z', name: 'Zed'),
      _f('orphan', parent: 'gone'),
    ]);

    test('children are sorted; orphans count as top level', () {
      expect(tree.children(null).map((f) => f.id), ['a', 'orphan', 'z']);
      expect(tree.children('a').single.id, 'b');
    });

    test('path, subtree, isWithin', () {
      expect(tree.pathTo('d').map((f) => f.id), ['a', 'b', 'c', 'd']);
      expect(tree.pathTo('missing'), isEmpty);
      expect(tree.subtreeIds('b'), {'b', 'c', 'd'});
      expect(tree.isWithin('d', 'a'), isTrue);
      expect(tree.isWithin('a', 'd'), isFalse);
    });

    test('access: locks on the path must be unlocked; children inherit', () {
      expect(tree.isAccessible('b', const {}), isTrue);
      expect(tree.isAccessible('c', const {}), isFalse);
      expect(tree.isAccessible('d', const {}), isFalse);
      expect(tree.isAccessible('d', {'c'}), isTrue);
      expect(tree.hiddenContentIds(const {}), {'c', 'd'});
      expect(tree.hiddenContentIds({'c'}), isEmpty);
    });

    test('stats roll up and skip hidden subtrees', () {
      final counts = {'a': 1, 'b': 2, 'c': 5, 'd': 7, null: 3};
      final all = tree.stats(counts);
      expect(all['a'], const FolderStats(folders: 3, documents: 15));
      final safe = tree.stats(counts, hidden: tree.hiddenContentIds(const {}));
      expect(safe['a'], const FolderStats(folders: 2, documents: 3));
      expect(safe['b'], const FolderStats(folders: 1, documents: 2));
    });

    test('a cycle never loops forever', () {
      final broken = FolderTree([_f('x', parent: 'y'), _f('y', parent: 'x')]);
      expect(broken.pathTo('x').length, 2);
      expect(broken.subtreeIds('x'), {'x', 'y'});
      expect(broken.stats(const {}), hasLength(2));
    });
  });

  group('FolderNames', () {
    test('validation', () {
      expect(FolderNames.validate('  ', const []), 'Enter a folder name');
      expect(FolderNames.validate('x' * 61, const []), contains('60'));
      expect(FolderNames.validate('Work', const ['work']), contains('exists'));
      expect(FolderNames.validate('Work', const ['Home']), isNull);
      expect(FolderNames.clean('  My   docs '), 'My docs');
    });
  });

  group('FolderTemplate', () {
    test('keys are unique and labels are country-neutral', () {
      final keys = FolderTemplate.all.map((t) => t.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      final banned = RegExp(
        r'\b(PAN|Aadhaar|US|USA|UK|India|SSN|IRS|HMRC)\b',
        caseSensitive: false,
      );
      for (final t in FolderTemplate.all) {
        for (final text in [t.label, t.hint, ...t.subfolders]) {
          expect(banned.hasMatch(text), isFalse, reason: text);
        }
        expect(FolderIcons.all, contains(t.icon));
        expect(FolderColors.all, contains(t.color));
      }
    });

    test('legacy categories map onto templates by key', () {
      for (final c in DocumentCategory.values) {
        expect(FolderTemplate.byKey(c.name)?.label, c.label);
      }
      expect(FolderTemplate.byKey('nope'), isNull);
    });
  });
}
