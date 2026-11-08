import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher_domain/commands/commands.dart';

import '../support/packs.dart';

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
    expect(await commands.run(const AddScreen(id: 'tv')), 1);
    expect(await commands.run(const AddScreen(id: 'tv')), 2);
    expect(await screensOf(c), ['home', 'tv', 'tv-2']);
  });

  test('a session undoes and redoes only what it did', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await commands.run(const AddScreen(id: 'mine'), session: 'one');
    await commands.run(const AddScreen(id: 'yours'), session: 'two');

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
      commands.run(const RemoveScreen('home'), session: 'one'),
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

    await commands.run(const SetConfig({'wallpaperEvery': 5}), session: 'one');
    await commands.run(const AddScreen(id: 'tv'), session: 'one');
    await commands.run(
      const Batch([
        SetConfig({
          'names': {'a': 'Films'},
        }),
        AddScreen(id: 'den'),
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
    await commands.run(const AddScreen(id: 'mine'), session: 'one');
    expect(await screensOf(c), ['home', 'mine']);
    expect((await c.read(configProvider.future)).ownLayout, isTrue);

    await commands.run(const ResetLayoutToStarting(), session: 'one');
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
      commands.run(const SetConfig({'layout': 1})),
      throwsA(isA<CommandRefused>()),
    );
    await expectLater(
      commands.run(
        SetConfig({
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

    await commands.run(const AddScreen(id: 'tv'), session: 'phone');
    await commands.undo(session: 'phone');
    await commands.redo(session: 'phone');

    expect([for (final e in heard) e.revision], [1, 2, 3]);
    expect(
      [for (final e in heard) e.action],
      [CommandAction.run, CommandAction.undo, CommandAction.redo],
    );
    expect(heard.every((e) => e.session == 'phone'), isTrue);
    // An undo logs the command that took the change back.
    expect(heard[1].command['type'], 'screen.remove');
    expect(
      [for (final e in (await commands.entriesAfter(1))!) e.revision],
      [2, 3],
    );
  });

  test('a command from a view someone else has changed is refused', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await commands.run(const AddScreen(id: 'mine'), session: 'phone');
    final seen = commands.revision;
    await commands.run(const AddScreen(id: 'theirs'), session: 'laptop');

    // The phone looked before the laptop's change.
    await expectLater(
      commands.run(
        const AddScreen(id: 'late'),
        session: 'phone',
        basedOn: seen,
      ),
      throwsA(isA<CommandRefused>()),
    );
    // Its own changes do not make it stale, and a current view is fine.
    await commands.run(
      const AddScreen(id: 'again'),
      session: 'phone',
      basedOn: commands.revision,
    );
    await commands.run(
      const AddScreen(id: 'more'),
      session: 'phone',
      basedOn: commands.revision - 1,
    );
    expect(await screensOf(c), ['home', 'mine', 'theirs', 'again', 'more']);
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
    await commands.run(const AddScreen(id: 'tv'), session: 'phone');
    await commands.run(const AddScreen(id: 'den'), session: 'phone');
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
      commands.run(const RemoveScreen('home')),
      throwsA(isA<CommandRefused>()),
    );
    expect(await commands.entriesAfter(0), isEmpty);
  });

  test('commands sent together each see the one before', () async {
    final c = await launcher();
    final commands = c.read(commandsProvider);
    await Future.wait([
      for (var i = 0; i < 5; i++) commands.run(const AddScreen(id: 'tv')),
    ]);
    expect(await screensOf(c), ['home', 'tv', 'tv-2', 'tv-3', 'tv-4', 'tv-5']);
  });

  test(
    'an undone removal brings the screen back with what was on it',
    () async {
      final c = await launcher();
      final commands = c.read(commandsProvider);
      await commands.run(const AddScreen(id: 'tv', name: 'TV room'));
      await commands.run(const RemoveScreen('tv'), session: 'one');
      await commands.undo(session: 'one');
      final layout = (await c.read(configProvider.future)).layout;
      expect(layout.screen('tv')?.root.name, 'TV room');
    },
  );
}
