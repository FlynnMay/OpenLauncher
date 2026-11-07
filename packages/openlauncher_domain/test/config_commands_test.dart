import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:test/test.dart';

final _start = Document(
  layout: Layout.blank(),
  settings: const {
    'names': {'a': 'Alpha'},
    'wallpaperEvery': 0,
    'place': null,
  },
);

void main() {
  prefabCommands();
  group('ResetLayoutToStarting', () {
    final starting = const AddScreen(id: 'start').apply(Layout.blank());
    final mine = const AddScreen(id: 'mine').apply(Layout.blank());
    final own = Document(layout: mine, startingLayout: starting);

    test('goes to the starting layout and is undone by the user\'s own', () {
      const reset = ResetLayoutToStarting();
      final after = reset.edit(own);
      expect(after.layout.toJson(), starting.toJson());
      expect(after.layoutIsTheUsers, isFalse);

      final undone = reset.undoing(own).edit(after);
      expect(undone.layout.toJson(), mine.toJson());
      expect(undone.layoutIsTheUsers, isTrue);
    });

    test('is sent as JSON, with the layout it restores', () {
      final restore = ReplaceWholeLayout(mine);
      expect(commandFromJson(restore.toJson()).toJson(), restore.toJson());
      expect(
        commandFromJson(const ResetLayoutToStarting().toJson()).type,
        'layout.reset',
      );
    });

    test('is refused when no starting layout is known', () {
      expect(
        () => const ResetLayoutToStarting().edit(Document(layout: mine)),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('SetConfig', () {
    test('sets whole values and is undone by the old ones', () {
      const command = SetConfig({
        'names': {'a': 'Films'},
        'place': {'name': 'Sydney'},
      });
      final after = command.edit(_start);
      expect(after.settings['names'], {'a': 'Films'});
      expect(after.settings['wallpaperEvery'], 0);

      final undo = command.undoing(_start);
      expect(undo.edit(after).settings, _start.settings);
      expect(undo.undoing(after).edit(_start).settings, after.settings);
    });

    test('refuses a key that is not a setting', () {
      expect(
        () => const SetConfig({'layout': 1}).edit(_start),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('is the same when sent as JSON', () {
      const command = SetConfig({'wallpaperEvery': 5});
      expect(commandFromJson(command.toJson()).toJson(), command.toJson());
    });
  });

  group('Batch', () {
    final batch = Batch([
      const SetConfig({'wallpaperEvery': 5}),
      const AddScreen(id: 'tv'),
      const SetConfig({'wallpaperEvery': 9}),
    ]);

    test('does each in turn, and one undo takes back all', () {
      final after = batch.edit(_start);
      expect(after.settings['wallpaperEvery'], 9);
      expect(after.layout.screens.map((s) => s.id), contains('tv'));

      final back = batch.undoing(_start).edit(after);
      expect(back.settings, _start.settings);
      expect(back.layout.toJson(), _start.layout.toJson());
    });

    test('is the same when sent as JSON', () {
      expect(commandFromJson(batch.toJson()).toJson(), batch.toJson());
    });
  });
}

void prefabCommands() {
  group('ChangePrefabs', () {
    Map<String, Object?> prefab(String id, String name) => {
      'id': id,
      'name': name,
    };
    final start = Document(
      layout: Layout.blank(),
      settings: {
        'prefabs': [prefab('a', 'A'), prefab('b', 'B')],
      },
    );
    List<Object?> prefabsOf(Document document) =>
        document.settings['prefabs']! as List<Object?>;

    test('changes, adds and removes by id, and is undone', () {
      final change = ChangePrefabs.turning(prefabsOf(start), [
        prefab('a', 'Alpha'),
        prefab('c', 'C'),
      ]);
      expect(change.upserted, [prefab('a', 'Alpha'), prefab('c', 'C')]);
      expect(change.removed, ['b']);

      final after = change.edit(start);
      expect(prefabsOf(after), [prefab('a', 'Alpha'), prefab('c', 'C')]);
      expect(change.undoing(start).edit(after).settings['prefabs'], [
        prefab('a', 'A'),
        prefab('b', 'B'),
      ]);
    });

    test('leaves a prefab another editor changed alone', () {
      final mine = ChangePrefabs.turning(prefabsOf(start), [
        prefab('a', 'Mine'),
        prefab('b', 'B'),
      ]);
      final theirs = start.copyWith(
        settings: {
          'prefabs': [prefab('a', 'A'), prefab('b', 'Theirs')],
        },
      );
      expect(prefabsOf(mine.edit(theirs)), [
        prefab('a', 'Mine'),
        prefab('b', 'Theirs'),
      ]);
    });

    test('is the same when sent as JSON, and nothing changed is empty', () {
      final change = ChangePrefabs(
        upserted: [prefab('a', 'x')],
        removed: const ['b'],
      );
      expect(commandFromJson(change.toJson()).toJson(), change.toJson());
      expect(
        ChangePrefabs.turning(prefabsOf(start), prefabsOf(start)).isEmpty,
        isTrue,
      );
    });
  });
}
