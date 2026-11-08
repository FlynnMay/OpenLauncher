import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';

import '../support/fake_tv.dart';
import '../support/packs.dart';

class _Tv extends TvApi {
  final sent = <String>[];

  @override
  Future<int> command(Map<String, Object?> command, {int? basedOn}) async {
    sent.add(describeCommand(commandFromJson(command)));
    return 0;
  }

  /// What the TV says of an action, by its name.
  final answers = <String, String>{};

  @override
  Future<String?> act(Act act) async {
    sent.add('${act.toJson()}');
    return answers[act.name];
  }
}

const _entity = Entity(
  id: 'system:app/a',
  category: appCategory,
  label: 'Alpha',
  data: {'package': 'a'},
  actions: {
    'open': EntityAction(
      run: 'os://apps/launch',
      bound: {'package': '{{self.package}}'},
      label: 'Open',
    ),
    'uninstall': EntityAction(
      run: 'os://apps/uninstall',
      bound: {'package': '{{self.package}}'},
      label: 'Uninstall',
    ),
  },
);

TvState _state() => TvState(
  entities: [
    _entity,
    const Entity(
      id: 'system:device',
      category: 'device',
      label: 'Device',
      actions: {
        'access': EntityAction(run: 'os://access/change', args: {'access': []}),
      },
    ),
  ],
  config: LauncherConfig(layout: homeLayout(['system:app/a'])),
  visuals: const [],
);

void main() {
  test('saving sends the TV only what changed', () async {
    final tv = _Tv();
    final store = TvConfigStore(TvCommands(tv), Future.value(_state()));
    final config = await store.load();

    await store.save(config);
    expect(tv.sent, isEmpty);

    await store.save(config.copyWith(toasts: const ToastOptions(seconds: 9)));
    expect(tv.sent, ['config toasts']);

    // What was sent is what the TV now has.
    await store.save(
      config.copyWith(
        toasts: const ToastOptions(seconds: 9),
        wallpaperEvery: 7,
      ),
    );
    expect(tv.sent, ['config toasts', 'config wallpaperEvery']);
  });

  test('the layout and the prefabs are not sent again, only edited', () async {
    final tv = _Tv();
    final store = TvConfigStore(TvCommands(tv), Future.value(_state()));
    final config = await store.load();

    expect(
      store.save(
        config.copyWith(layout: config.layout.without({'system:app/a'})),
      ),
      throwsStateError,
    );
    final prefab = Prefab(
      id: 'mine',
      name: 'Mine',
      root: Node(id: 'root'),
    );
    expect(store.save(config.copyWith(prefabs: [prefab])), throwsStateError);
    expect(tv.sent, isEmpty);
  });

  test('commands the TV announces are heard apart from its states', () async {
    final state = jsonEncode({
      'entities': [],
      'layout': homeLayout().toJson(),
      'config': <String, Object?>{},
      'visuals': [],
      'widgetProviders': [],
    });
    final entry = jsonEncode(
      const CommandLogEntry(
        revision: 3,
        session: 'phone',
        action: CommandAction.run,
        command: {'type': 'screen.add', 'id': 'tv'},
      ).toJson(),
    );
    final api = TvApi(
      client: MockClient.streaming(
        (request, body) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: $state\n\nevent: command\ndata: $entry\n\ndata: $state\n\n',
            ),
          ),
          200,
        ),
      ),
    );
    final heard = <CommandLogEntry>[];
    api.commandEntries.listen(heard.add);

    expect(api.knownRevision, isNull);
    final states = await api.states().take(2).toList();
    expect(states, hasLength(2));
    expect(heard.single.revision, 3);
    expect(api.knownRevision, 3);
    expect(heard.single.session, 'phone');
  });

  test('a starting layout is not sent; reverting to it is', () async {
    final tv = _Tv();
    final store = TvConfigStore(
      TvCommands(tv),
      Future.value(
        TvState(
          entities: const [_entity],
          config: startingConfig,
          visuals: const [],
        ),
      ),
    );
    final start = await store.load();

    // The editor has the pack's own; another setting changing leaves it.
    final saved = start.copyWith(
      layout: homeLayout(['system:app/a']),
      ownLayout: false,
      toasts: const ToastOptions(seconds: 9),
    );
    await store.save(saved);
    expect(tv.sent, ['config toasts']);

    // Reverting to the starting layout is what is sent when the TV had its own.
    final ownTv = _Tv();
    final own = TvConfigStore(TvCommands(ownTv), Future.value(_state()));
    final had = await own.load();
    await own.save(had.copyWith(layout: homeLayout(), ownLayout: false));
    expect(ownTv.sent, ['revert']);
  });

  testWidgets('the launcher runs on what the TV sends, and edits go back', (
    tester,
  ) async {
    final tv = _Tv();
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
        ],
        child: MaterialApp(
          home: FittedBox(
            child: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const Stage(editing: true);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The launcher's own home screen, drawing the TV's entity: with no
    // picture, its name is on it as well as under it.
    expect(find.text('Alpha'), findsNWidgets(2));

    // An edit made here reaches the TV as it is.
    final layout = ref.read(configProvider).value!.layout;
    final card = layout.items.firstWhere(
      (item) => item.handed.contains('system:app/a'),
    );
    await ref
        .read(commandsProvider)
        .run(
          EditSlice([
            SliceEdit(LayoutAddress(card.id), const [RemoveNode()]),
          ]),
        );
    await tester.pumpAndSettle();
    expect(tv.sent, ['edit 1']);
  });

  testWidgets('an entity pressed here is opened on the TV', (tester) async {
    final tv = _Tv();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
        ],
        child: const MaterialApp(home: FittedBox(child: Stage(editing: false))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    expect(tv.sent, ['{do: open, entity: system:app/a}']);
  });

  test(
    'what plays on the TV is what the launcher here says is playing',
    () async {
      final states = StreamController<TvState>();
      final container = ProviderContainer(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(_Tv()),
          tvStateProvider.overrideWith((ref) => states.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(nowPlayingProvider, (_, _) {});

      states.add(_state());
      await pumpEventQueue();
      expect(container.read(nowPlayingProvider).value, isNull);

      states.add(
        TvState(
          entities: const [_entity],
          config: LauncherConfig(layout: homeLayout(['system:app/a'])),
          visuals: const [],
          nowPlaying: NowPlaying(
            packageName: 'a',
            appLabel: 'A',
            title: 'Song',
            playing: true,
          ),
        ),
      );
      await pumpEventQueue();
      expect(container.read(nowPlayingProvider).value?.title, 'Song');
    },
  );

  test(
    'what the TV itself does is sent to it, the rest is done here',
    () async {
      final tv = _Tv()..answers['uninstall'] = 'Asked on the TV.';
      final container = ProviderContainer(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
        ],
      );
      addTearDown(container.dispose);
      // As the screen does: nothing is read from the TV for no one.
      container.listen(entitiesProvider, (_, _) {});
      final actions = container.read(actionRunnerProvider);

      // The TV is sent the act as written, entity and all.
      expect(
        await actions.run(const Act('uninstall', {'entity': 'system:app/a'})),
        'Asked on the TV.',
      );
      await actions.run(
        const Act('access', {
          'entity': 'system:device',
          'access': 'homeButton',
        }),
      );
      expect(tv.sent, [
        '{do: uninstall, entity: system:app/a}',
        '{do: access, entity: system:device, access: homeButton}',
      ]);
      // So is an address the TV answers, and the TV's own updater.
      await actions.run(const Act('os://apps/launch', {'package': 'a'}));
      await actions.run(const Act('launcher://updates/check'));
      expect(tv.sent.skip(2), [
        '{run: os://apps/launch, with: {package: a}}',
        '{run: launcher://updates/check}',
      ]);
      tv.sent.removeRange(2, 4);
      // One that names no entity is declined here and never sent.
      expect(actions.run(const Act('access')), throwsA(isA<ImproperAct>()));

      // Setting a variable is the page's own business.
      await actions.run(
        const Act('launcher://variables/set', {
          'of': 'x',
          'var': 'on',
          'value': 2,
        }),
      );
      expect(tv.sent, hasLength(2));
    },
  );

  group('where an act goes depends on the mode', () {
    late _Tv tv;
    late ProviderContainer container;

    setUp(() {
      tv = _Tv();
      container = ProviderContainer(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
        ],
      );
      addTearDown(container.dispose);
      container.listen(entitiesProvider, (_, _) {});
    });

    Future<String?> run(Act act) =>
        container.read(actionRunnerProvider).run(act);

    test('testing says what only the TV could do and sends nothing', () async {
      container.read(editorModeProvider.notifier).choose(EditorMode.test);
      expect(
        await run(const Act('os://apps/launch', {'package': 'a'})),
        'Test: would open an app (package: a)',
      );
      expect(
        await run(const Act('launcher://updates/check')),
        'Test: would check for an update of the launcher',
      );
      expect(tv.sent, isEmpty);
    });

    test('remote sends every act to the TV', () async {
      container.read(editorModeProvider.notifier).choose(EditorMode.remote);
      await run(const Act('os://apps/launch', {'package': 'a'}));
      await run(
        const Act('launcher://variables/set', {
          'of': 'x',
          'var': 'on',
          'value': 2,
        }),
      );
      expect(tv.sent, [
        '{run: os://apps/launch, with: {package: a}}',
        '{run: launcher://variables/set, with: {of: x, var: on, value: 2}}',
      ]);
    });
  });

  test('what the TV allows is what the TV says', () async {
    final container = ProviderContainer(
      overrides: [
        ...tvOverrides,
        systemContents,
        tvApiProvider.overrideWithValue(_Tv()),
        tvStateProvider.overrideWith(
          (ref) => Stream.value(
            TvState(
              entities: const [_entity],
              config: LauncherConfig(layout: homeLayout(['system:app/a'])),
              visuals: const [],
              access: const {Access.homeButton: false},
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    for (final access in Access.values) {
      container.listen(accessProvider(access), (_, _) {});
    }
    expect(
      await container.read(accessProvider(Access.homeButton).future),
      isFalse,
    );
    // Allowed unless the TV says not.
    expect(
      await container.read(accessProvider(Access.notifications).future),
      isTrue,
    );
  });
}
