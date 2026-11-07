import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:test/test.dart';

List<String> _ids(Layout layout) => [for (final s in layout.screens) s.id];

void main() {
  final blank = Layout.blank();

  group('screen commands', () {
    test('AddScreen adds an empty screen with a free id', () {
      final once = const AddScreen(name: 'Kitchen').apply(blank);
      final twice = const AddScreen(name: 'Kitchen').apply(once);
      expect(_ids(twice), ['home', 'kitchen', 'kitchen-2']);
      expect(once.screen('kitchen')!.root.name, 'Kitchen');
    });

    test('RemoveScreen refuses the last screen and one that is not there', () {
      expect(
        () => const RemoveScreen('home').apply(blank),
        throwsA(isA<CommandRefused>()),
      );
      final two = const AddScreen(id: 'tv').apply(blank);
      expect(
        () => const RemoveScreen('nope').apply(two),
        throwsA(isA<CommandRefused>()),
      );
      expect(_ids(const RemoveScreen('tv').apply(two)), ['home']);
    });

    test('each command is undone by its inverse', () {
      final two = const AddScreen(id: 'tv').apply(blank);
      final added = const AddScreen(id: 'tv');
      expect(_ids(added.inverse(blank).apply(two)), ['home']);

      final removed = const RemoveScreen('home');
      final back = removed.inverse(two).apply(removed.apply(two));
      expect(_ids(back), ['home', 'tv']);
    });

    test('an undone add takes the screen it made, not one with its id', () {
      final first = const AddScreen(id: 'tv').apply(blank);
      final taken = const AddScreen(id: 'tv');
      expect(taken.idIn(first), 'tv-2');
      expect(_ids(taken.inverse(first).apply(taken.apply(first))), [
        'home',
        'tv',
      ]);
    });

    test('a removed screen comes back as it was, where it was', () {
      final three = const AddScreen(id: 'c')
          .apply(const AddScreen(id: 'b').apply(blank));
      const removal = RemoveScreen('b');
      final restored = removal.inverse(three).apply(removal.apply(three));
      expect(_ids(restored), ['home', 'b', 'c']);
    });
  });

  group('commandFromJson', () {
    test('reads what toJson writes', () {
      final two = const AddScreen(id: 'tv').apply(blank);
      for (final command in <Command>[
        const AddScreen(id: 'x', name: 'X'),
        const RemoveScreen('x'),
        RestoreScreen(two.screen('tv')!, 1),
      ]) {
        expect(commandFromJson(command.toJson()).toJson(), command.toJson());
      }
    });

    test('refuses what is not a command, or is not for the layout', () {
      expect(
        () => commandFromJson({'type': 'nope'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => commandFromJson({'type': 'screen.remove'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => commandFromJson({'type': 'screen.add', 'target': 'prefab:a'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CommandHistory', () {
    test('undo and redo go back and forth, per session', () {
      final history = CommandHistory();
      const undo = RemoveScreen('a');
      history.recordChange('one', undo);
      expect(history.nextUndo('two'), isNull);
      expect(history.nextUndo('one'), same(undo));

      const redo = AddScreen(id: 'a');
      history.recordUndo('one', redo);
      expect(history.nextUndo('one'), isNull);
      expect(history.nextRedo('one'), same(redo));

      history.recordRedo('one', undo);
      expect(history.nextUndo('one'), same(undo));
      expect(history.nextRedo('one'), isNull);
    });

    test('a new change clears what could be redone', () {
      final history = CommandHistory()
        ..recordChange('one', const RemoveScreen('a'))
        ..recordUndo('one', const AddScreen(id: 'a'))
        ..recordChange('one', const RemoveScreen('b'));
      expect(history.nextRedo('one'), isNull);
    });

    test('keeps only the last [limit] steps', () {
      final history = CommandHistory(limit: 2)
        ..recordChange('one', const RemoveScreen('a'))
        ..recordChange('one', const RemoveScreen('b'))
        ..recordChange('one', const RemoveScreen('c'));
      history.recordUndo('one', const AddScreen());
      history.recordUndo('one', const AddScreen());
      expect(history.nextUndo('one'), isNull);
    });
  });
}
