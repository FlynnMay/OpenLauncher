import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';

import '../support/packs.dart';

Command addScreen(String id, {String name = ''}) => EditSlice([
  SliceEdit(const ConfigAddress(), [AddScreen(id: id, label: name)]),
]);

Command removeScreen(String id) => EditSlice([
  SliceEdit(ScreenAddress(id), const [RemoveScreen()]),
]);

Command setConfig(Map<String, Object?> values) => EditSlice([
  SliceEdit(const ConfigAddress(), [
    for (final MapEntry(:key, :value) in values.entries) SetSetting(key, value),
  ]),
]);

void main() {
  Future<ProviderContainer> launcher() async {
    final c = ProviderContainer(
      overrides: [
        ...launcherOverrides,
        commandHistoryStoreProvider.overrideWithValue(
          MemoryCommandHistoryStore(),
        ),
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(layout: Layout.blank())),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(configProvider.future);
    return c;
  }

  Future<List<String>> screensOf(ProviderContainer c) async => [
    for (final screen in (await c.read(configProvider.future)).layout.screens)
      screen.id,
  ];

  test('a command changes the saved layout and counts a revision', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    expect(await commands.run(addScreen('tv')), 1);
    expect(await commands.run(addScreen('tv')), 2);
    expect(await screensOf(c), ['home', 'tv', 'tv-2']);
  });

  test('a session undoes and redoes only what it did', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await commands.run(addScreen('mine'), session: 'one');
    await commands.run(addScreen('yours'), session: 'two');

    await commands.undo(session: 'one');
    expect(await screensOf(c), ['home', 'yours']);

    await commands.redo(session: 'one');
    expect(await screensOf(c), ['home', 'mine', 'yours']);

    await expectLater(
      commands.undo(session: 'three'),
      throwsA(isA<CommandRefused>()),
    );
  });

  test('a refused command changes nothing and is not undoable', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await expectLater(
      commands.run(removeScreen('home'), session: 'one'),
      throwsA(isA<CommandRefused>()),
    );
    expect(await screensOf(c), ['home']);
    await expectLater(
      commands.undo(session: 'one'),
      throwsA(isA<CommandRefused>()),
    );
  });

  test('settings are set and undone with the layout in one history', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    Future<LauncherConfig> config() => c.read(configProvider.future);

    await commands.run(setConfig({'wallpaperEvery': 5}), session: 'one');
    await commands.run(addScreen('tv'), session: 'one');
    await commands.run(
      EditSlice([
        const SliceEdit(ConfigAddress(), [
          SetSetting('names', {'a': 'Films'}),
          AddScreen(id: 'den'),
        ]),
      ]),
      session: 'one',
    );
    expect((await config()).names, {'a': 'Films'});
    expect(await screensOf(c), ['home', 'tv', 'den']);

    await commands.undo(session: 'one');
    expect((await config()).names, isEmpty);
    expect(await screensOf(c), ['home', 'tv']);
    await commands.undo(session: 'one');
    await commands.undo(session: 'one');
    expect((await config()).wallpaperEvery, 0);
    await commands.redo(session: 'one');
    expect((await config()).wallpaperEvery, 5);
  });

  test('a reset to the starting layout is undone', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await commands.run(addScreen('mine'), session: 'one');
    expect(await screensOf(c), ['home', 'mine']);
    expect((await c.read(configProvider.future)).ownLayout, isTrue);

    await commands.run(
      EditSlice([
        const SliceEdit(ConfigAddress(), [ResetLayout()]),
      ]),
      session: 'one',
    );
    expect(await screensOf(c), ['system:home']);
    expect((await c.read(configProvider.future)).ownLayout, isFalse);

    await commands.undo(session: 'one');
    expect(await screensOf(c), ['home', 'mine']);
    expect((await c.read(configProvider.future)).ownLayout, isTrue);

    await commands.redo(session: 'one');
    expect((await c.read(configProvider.future)).ownLayout, isFalse);
  });

  test('a setting that does not exist or is too long is refused', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await expectLater(
      commands.run(setConfig({'layout': 1})),
      throwsA(isA<CommandRefused>()),
    );
    await expectLater(
      commands.run(
        setConfig({
          'names': {'a': 'x' * 61},
        }),
      ),
      throwsA(isA<CommandRefused>()),
    );
  });

  test('every command done is logged, with who did it and how', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    final heard = <CommandLogEntry>[];
    commands.entries.listen(heard.add);

    await commands.run(addScreen('tv'), session: 'phone');
    await commands.undo(session: 'phone');
    await commands.redo(session: 'phone');

    expect([for (final e in heard) e.revision], [1, 2, 3]);
    expect(
      [for (final e in heard) e.action],
      [CommandAction.run, CommandAction.undo, CommandAction.redo],
    );
    expect(heard.every((e) => e.session == 'phone'), isTrue);
    // An undo logs the command that took the change back.
    expect(heard[1].command['type'], 'slice.edit');
    expect(
      [for (final e in (await commands.entriesAfter(1))!) e.revision],
      [2, 3],
    );
  });

  test('a command from a view someone else has changed is refused', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await commands.run(addScreen('mine'), session: 'phone');
    final seen = commands.revision;
    await commands.run(addScreen('theirs'), session: 'laptop');

    // The phone looked before the laptop's change.
    await expectLater(
      commands.run(addScreen('late'), session: 'phone', basedOn: seen),
      throwsA(isA<CommandRefused>()),
    );
    // Its own changes do not make it stale, and a current view is fine.
    await commands.run(
      addScreen('again'),
      session: 'phone',
      basedOn: commands.revision,
    );
    await commands.run(
      addScreen('more'),
      session: 'phone',
      basedOn: commands.revision - 1,
    );
    expect(await screensOf(c), ['home', 'mine', 'theirs', 'again', 'more']);
  });

  test('a stale view is refused only where someone else changed it', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    Command name(String app, String value) => EditSlice([
      SliceEdit(const ConfigAddress(), [SetEntry('names', app, value)]),
    ]);
    final seen = commands.revision;
    await commands.run(name('a', 'Alpha'), session: 'phone');

    // The laptop looked before, and changes something else.
    await commands.run(name('b', 'Beta'), session: 'laptop', basedOn: seen);
    // Not the same entry the phone changed.
    await expectLater(
      commands.run(name('a', 'Late'), session: 'laptop', basedOn: seen),
      throwsA(isA<CommandRefused>()),
    );
    expect((await c.read(configProvider.future)).names, {
      'a': 'Alpha',
      'b': 'Beta',
    });
  });

  test('what a session could undo is still there after a restart', () async {
    final kept = MemoryCommandHistoryStore();
    final saved = MemoryConfigStore(LauncherConfig(layout: Layout.blank()));
    ProviderContainer started() {
      final c = ProviderContainer(
        overrides: [
          ...launcherOverrides,
          commandHistoryStoreProvider.overrideWithValue(kept),
          configStoreProvider.overrideWithValue(saved),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final before = started();
    await before.read(configProvider.future);
    final commands = before.read(commandsProvider);
    await commands.run(addScreen('tv'), session: 'phone');
    await commands.run(addScreen('den'), session: 'phone');
    await commands.undo(session: 'phone');
    before.dispose();

    // The app starts again: the layout is the same, the history is back.
    final after = started();
    await after.read(configProvider.future);
    final restarted = after.read(commandsProvider);
    expect(restarted.revision, 0);
    await restarted.redo(session: 'phone');
    expect(await screensOf(after), ['home', 'tv', 'den']);
    await restarted.undo(session: 'phone');
    await restarted.undo(session: 'phone');
    expect(await screensOf(after), ['home']);
  });

  test('a history that cannot be read is an empty one', () async {
    final c = ProviderContainer(
      overrides: [
        ...launcherOverrides,
        commandHistoryStoreProvider.overrideWithValue(
          MemoryCommandHistoryStore()..save({'phone': 'nonsense'}),
        ),
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(layout: Layout.blank())),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(configProvider.future);
    await expectLater(
      c.read(commandsProvider).undo(session: 'phone'),
      throwsA(isA<CommandRefused>()),
    );
  });

  test('a refused command is not logged', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await expectLater(
      commands.run(removeScreen('home')),
      throwsA(isA<CommandRefused>()),
    );
    expect(await commands.entriesAfter(0), isEmpty);
  });

  test('commands sent together each see the one before', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await Future.wait([
      for (var i = 0; i < 5; i++) commands.run(addScreen('tv')),
    ]);
    expect(await screensOf(c), ['home', 'tv', 'tv-2', 'tv-3', 'tv-4', 'tv-5']);
  });

  test(
    'an undone removal brings the screen back with what was on it',
    () async {
      final c = await launcher();
      final commands = c.read(commandsProvider);
      await commands.run(addScreen('tv', name: 'TV room'));
      await commands.run(removeScreen('tv'), session: 'one');
      await commands.undo(session: 'one');
      final layout = (await c.read(configProvider.future)).layout;
      expect(layout.screen('tv')?.root.name, 'TV room');
    },
  );
}
