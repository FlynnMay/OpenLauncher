import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/slice/slice.dart';
import 'package:test/test.dart';

List<String> _ids(Layout layout) => [for (final s in layout.screens) s.id];

/// A command that adds or removes the screen [id], to have something to keep.
Command _remove(String id) => EditSlice([
  SliceEdit(ScreenAddress(id), const [RemoveScreen()]),
]);

Command _add(String id) => EditSlice([
  SliceEdit(const ConfigAddress(), [AddScreen(id: id)]),
]);

void main() {
  historyKeptAsJson();

  group('commandFromJson', () {
    test('reads what toJson writes', () {
      final command = EditSlice([
        SliceEdit(const ConfigAddress(), [
          const AddScreen(id: 'x', label: 'X'),
          const SetSetting('wallpaperEvery', 5),
          const SetEntry('names', 'a', 'Alpha'),
          const SetStartup(screenId: 'x', remember: true),
          const ResetLayout(),
        ]),
        const SliceEdit(ScreenAddress('x'), [
          RenameScreen('Y'),
          DuplicateScreen(),
          RemoveScreen(),
        ]),
      ]);
      expect(commandFromJson(command.toJson()).toJson(), command.toJson());
    });

    test('refuses what is not a command', () {
      expect(
        () => commandFromJson({'type': 'nope'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => commandFromJson({'type': 'screen.remove'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CommandHistory', () {
    test('undo and redo go back and forth, per session', () {
      final history = CommandHistory();
      final undo = _remove('a');
      history.recordChange('one', undo);
      expect(history.nextUndo('two'), isNull);
      expect(history.nextUndo('one'), same(undo));

      final redo = _add('a');
      history.recordUndo('one', redo);
      expect(history.nextUndo('one'), isNull);
      expect(history.nextRedo('one'), same(redo));

      history.recordRedo('one', undo);
      expect(history.nextUndo('one'), same(undo));
      expect(history.nextRedo('one'), isNull);
    });

    test('a new change clears what could be redone', () {
      final history = CommandHistory()
        ..recordChange('one', _remove('a'))
        ..recordUndo('one', _add('a'))
        ..recordChange('one', _remove('b'));
      expect(history.nextRedo('one'), isNull);
    });

    test('keeps only the last [limit] steps', () {
      final history = CommandHistory(limit: 2)
        ..recordChange('one', _remove('a'))
        ..recordChange('one', _remove('b'))
        ..recordChange('one', _remove('c'));
      history.recordUndo('one', _add('a'));
      history.recordUndo('one', _add('b'));
      expect(history.nextUndo('one'), isNull);
    });
  });

  group('what a command changes', () {
    Set<String> areas(String address, List<SliceOp> ops) =>
        EditSlice([SliceEdit(Address.parse(address), ops)]).areas;

    const set = SetField('text', 'size', 3);

    test(
      'edits to different nodes do not overlap, a node and its child do',
      () {
        expect(
          areasOverlap(areas('layout:a', [set]), areas('layout:b', [set])),
          isFalse,
        );
        expect(
          areasOverlap(areas('layout:a', [set]), areas('layout:a', [set])),
          isTrue,
        );
        expect(
          areasOverlap(
            areas('layout:a', [set]),
            areas('layout:a/image', [set]),
          ),
          isTrue,
        );
        expect(
          areasOverlap(
            areas('layout:a/image', [set]),
            areas('layout:a/name', [set]),
          ),
          isFalse,
        );
      },
    );

    test('children of one prefab are apart, the prefab as a whole is not', () {
      expect(
        areasOverlap(areas('prefab:p/x', [set]), areas('prefab:p/y', [set])),
        isFalse,
      );
      expect(
        areasOverlap(
          areas('prefab:p/x', [set]),
          areas('prefab:p/', const [DeletePrefab()]),
        ),
        isTrue,
      );
    });

    test(
      'settings are apart from nodes, and entries of one map from each other',
      () {
        final name = areas('/', const [SetEntry('names', 'a', 'A')]);
        expect(
          areasOverlap(name, areas('/', const [SetEntry('names', 'b', 'B')])),
          isFalse,
        );
        expect(
          areasOverlap(name, areas('/', const [SetEntry('names', 'a', 'Z')])),
          isTrue,
        );
        expect(
          areasOverlap(name, areas('/', const [SetSetting('names', {})])),
          isTrue,
        );
        expect(areasOverlap(name, areas('layout:a', [set])), isFalse);
      },
    );

    test('the layout as a whole overlaps every node and screen', () {
      final whole = areas('/', const [AddScreen(id: 'x')]);
      expect(areasOverlap(whole, areas('layout:a', [set])), isTrue);
      expect(
        areasOverlap(whole, areas('screen:home', const [RenameScreen('H')])),
        isTrue,
      );
      expect(
        areasOverlap(whole, areas('/', const [SetSetting('toasts', {})])),
        isFalse,
      );
    });

    test('a command that says nothing changes everything', () {
      expect(
        areasOverlap(const {everywhere}, areas('layout:a', [set])),
        isTrue,
      );
    });
  });

  group('screens', () {
    final blank = Document(layout: Layout.blank());

    Document run(Document document, List<SliceEdit> edits) =>
        EditSlice(edits).edit(document);

    test('an added screen has a free id, and is removed again by its undo', () {
      final command = EditSlice([
        SliceEdit(const ConfigAddress(), [const AddScreen(label: 'Kitchen')]),
      ]);
      final once = command.edit(blank);
      final twice = command.edit(once);
      expect(_ids(twice.layout), ['home', 'kitchen', 'kitchen-2']);
      expect(once.layout.screen('kitchen')!.root.name, 'Kitchen');
      // The undo takes away the screen it made, not one with the same id.
      final back = command.undoing(once).edit(twice);
      expect(_ids(back.layout), ['home', 'kitchen']);
    });

    test('the last screen stays, and one that is not there is refused', () {
      expect(() => _remove('home').edit(blank), throwsA(isA<CommandRefused>()));
      final two = run(blank, [
        const SliceEdit(ConfigAddress(), [AddScreen(id: 'tv')]),
      ]);
      expect(() => _remove('nope').edit(two), throwsA(isA<CommandRefused>()));
      expect(_ids(_remove('tv').edit(two).layout), ['home']);
    });

    test('a removed screen comes back as it was, where it was', () {
      final three = run(blank, [
        const SliceEdit(ConfigAddress(), [AddScreen(id: 'b')]),
        const SliceEdit(ConfigAddress(), [AddScreen(id: 'c')]),
      ]);
      final command = _remove('b');
      final restored = command.undoing(three).edit(command.edit(three));
      expect(_ids(restored.layout), ['home', 'b', 'c']);
    });

    test('a rename is undone by the old label', () {
      final two = run(blank, [
        const SliceEdit(ConfigAddress(), [AddScreen(id: 'tv', label: 'TV')]),
      ]);
      final command = EditSlice([
        const SliceEdit(ScreenAddress('tv'), [RenameScreen('Lounge')]),
      ]);
      final renamed = command.edit(two);
      expect(renamed.layout.screen('tv')!.root.name, 'Lounge');
      expect(
        command.undoing(two).edit(renamed).layout.screen('tv')!.root.name,
        'TV',
      );
      expect(
        () => EditSlice([
          const SliceEdit(ScreenAddress('nope'), [RenameScreen('x')]),
        ]).edit(two),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('startup changes only what it is given, and is undone', () {
      final two = run(blank, [
        const SliceEdit(ConfigAddress(), [AddScreen(id: 'tv')]),
      ]);
      final on = EditSlice([
        const SliceEdit(ConfigAddress(), [SetStartup(screenId: 'tv')]),
      ]).edit(two);
      expect(on.layout.startup.screen, 'tv');
      final remember = EditSlice([
        const SliceEdit(ConfigAddress(), [SetStartup(remember: true)]),
      ]);
      final remembered = remember.edit(on);
      expect(remembered.layout.startup.screen, 'tv');
      expect(remembered.layout.startup.remember, isTrue);
      expect(
        remember.undoing(on).edit(remembered).layout.startup,
        on.layout.startup,
      );
      expect(
        () => EditSlice([
          const SliceEdit(ConfigAddress(), [SetStartup(screenId: 'nope')]),
        ]).edit(two),
        throwsA(isA<CommandRefused>()),
      );
    });

    test(
      'a copy carries the pictures of its nodes, and one undo removes both',
      () {
        final two = run(blank, [
          const SliceEdit(ConfigAddress(), [AddScreen(id: 'tv', label: 'TV')]),
        ]);
        final withNode = Document(
          layout: two.layout,
          settings: {
            'iconOverrides': {
              Layout.pictureKey(two.layout.screen('tv')!.root.id): '/a.png',
            },
            'iconSources': <String, Object?>{},
          },
        );
        final copy = EditSlice([
          const SliceEdit(ScreenAddress('tv'), [DuplicateScreen()]),
        ]);
        final after = copy.edit(withNode);
        expect(after.layout.screens.map((s) => s.id), ['home', 'tv', 'tv-2']);
        expect(
          (after.settings['iconOverrides']! as Map).keys,
          contains(Layout.pictureKey(after.layout.screen('tv-2')!.root.id)),
        );
        final back = copy.undoing(withNode).edit(after);
        expect(back.layout.screens.map((s) => s.id), ['home', 'tv']);
        expect(
          back.settings['iconOverrides'],
          withNode.settings['iconOverrides'],
        );
      },
    );
  });
}

void historyKeptAsJson() {
  group('CommandHistory as JSON', () {
    test('what a session can undo and redo comes back as it was', () {
      final history = CommandHistory()
        ..recordChange('phone', _remove('a'))
        ..recordChange('phone', _remove('b'))
        ..recordUndo('phone', _add('b'))
        ..recordChange('laptop', _remove('c'));

      final back = CommandHistory.fromJson(
        history.toJson(),
        read: commandFromJson,
      );
      expect(back.nextUndo('phone')!.toJson(), _remove('a').toJson());
      expect(back.nextRedo('phone')!.toJson(), _add('b').toJson());
      expect(back.nextUndo('laptop')!.toJson(), _remove('c').toJson());
      expect(back.nextUndo('nobody'), isNull);
    });

    test('a session with a command that cannot be read starts empty', () {
      final back = CommandHistory.fromJson({
        'good': {
          'undo': [_remove('a').toJson()],
        },
        'bad': {
          'undo': [
            {'type': 'from-a-newer-version'},
          ],
        },
      }, read: commandFromJson);
      expect(back.nextUndo('good'), isNotNull);
      expect(back.nextUndo('bad'), isNull);
    });

    test('nothing, or nonsense, is an empty history', () {
      expect(
        CommandHistory.fromJson(null, read: commandFromJson).nextUndo('x'),
        isNull,
      );
      expect(
        CommandHistory.fromJson(42, read: commandFromJson).nextUndo('x'),
        isNull,
      );
    });
  });
}
