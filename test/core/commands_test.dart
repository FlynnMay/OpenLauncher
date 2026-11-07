import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher_domain/commands/commands.dart';

import '../support/packs.dart';

void main() {
  Future<ProviderContainer> launcher() async {
    final c = ProviderContainer(
      overrides: [
        ...packOverrides,
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
