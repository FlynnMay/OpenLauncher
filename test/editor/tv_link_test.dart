import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_link.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

class _Tv extends TvApi {
  final sent = <String>[];

  @override
  Future<void> setLayout(Layout layout) async => sent.add('layout');

  @override
  Future<void> setConfig(Map<String, Object?> changed) async =>
      sent.add('config ${changed.keys.join(' ')}');

  /// What the TV says of an action, by its name.
  final answers = <String, String>{};

  @override
  Future<String?> act(Act act) async {
    sent.add('${act.toJson()}');
    return answers[act.name];
  }
}

const _entity = Entity(
  id: 'app:a',
  category: appCategory,
  label: 'Alpha',
  data: {'package': 'a'},
  actions: appActions,
);

TvState _state() => TvState(
  entities: [
    _entity,
    builtInEntities.byId('system')!,
    builtInEntities.byId('variables')!,
  ],
  config: LauncherConfig(layout: Layout.initial(['app:a'])),
  components: const [],
);

void main() {
  test('saving sends the TV only what changed', () async {
    final tv = _Tv();
    final store = TvConfigStore(tv, Future.value(_state()));
    final config = await store.load();

    await store.save(config);
    expect(tv.sent, isEmpty);

    final emptied = config.copyWith(layout: config.layout.without({'app:a'}));
    await store.save(emptied);
    expect(tv.sent, ['layout']);

    // What was sent is what the TV now has.
    await store.save(emptied.copyWith(toasts: const ToastOptions(seconds: 9)));
    expect(tv.sent, ['layout', 'config toasts']);
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

    // A change made through the launcher's own controller reaches the TV.
    final layout = ref.read(configProvider).value!.layout;
    await ref
        .read(configProvider.notifier)
        .setLayout(layout.without({'app:a'}));
    await tester.pumpAndSettle();
    expect(tv.sent, ['layout']);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('an entity pressed here is opened on the TV', (tester) async {
    final tv = _Tv();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
        ],
        child: const MaterialApp(home: FittedBox(child: Stage(editing: false))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    expect(tv.sent, ['{do: open, entity: app:a}']);
  });

  test(
    'what plays on the TV is what the launcher here says is playing',
    () async {
      final states = StreamController<TvState>();
      final container = ProviderContainer(
        overrides: [
          ...tvOverrides,
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
          config: LauncherConfig(layout: Layout.initial(['app:a'])),
          components: const [],
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
      final tv = _Tv()..answers['forceStop'] = 'Alpha was stopped.';
      final container = ProviderContainer(
        overrides: [
          ...tvOverrides,
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
        await actions.run(const Act('forceStop', {'entity': 'app:a'})),
        'Alpha was stopped.',
      );
      await actions.run(
        const Act('homeButton', {'entity': 'system', 'enabled': false}),
      );
      expect(tv.sent, [
        '{do: forceStop, entity: app:a}',
        '{do: homeButton, entity: system, enabled: false}',
      ]);
      // One that names no entity is declined here and never sent.
      expect(actions.run(const Act('setup')), throwsA(isA<ImproperAct>()));

      // Setting a variable is the page's own business.
      await actions.run(
        const Act('set', {
          'entity': 'variables',
          'of': 'x',
          'var': 'on',
          'value': 1,
        }),
      );
      expect(tv.sent, hasLength(2));
    },
  );

  test('how the Home button stands is what the TV says', () async {
    final container = ProviderContainer(
      overrides: [
        ...tvOverrides,
        tvApiProvider.overrideWithValue(_Tv()),
        tvStateProvider.overrideWith(
          (ref) => Stream.value(
            TvState(
              entities: const [_entity],
              config: LauncherConfig(layout: Layout.initial(['app:a'])),
              components: const [],
              homeButton: false,
              canManageHomeButton: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
      ..listen(homeButtonEnabledProvider, (_, _) {})
      ..listen(canManageHomeButtonProvider, (_, _) {});
    expect(await container.read(homeButtonEnabledProvider.future), isFalse);
    expect(await container.read(canManageHomeButtonProvider.future), isTrue);
  });
}
