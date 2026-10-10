import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_link.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

class _Tv extends TvApi {
  final sent = <String>[];

  @override
  Future<void> setLayout(Layout layout) async => sent.add('layout');

  @override
  Future<void> setOptions(LauncherConfig config) async => sent.add('options');

  /// What the TV answers a press with, by what was pressed.
  final answers = <String, Map<String, Object?>>{};

  @override
  Future<Map<Object?, Object?>> press(
    String what, {
    String? card,
    Map<String, Object?> more = const {},
  }) async {
    sent.add([what, ?card, if (more.isNotEmpty) more].join(' '));
    return answers[what] ?? const {};
  }
}

const _card = LauncherCard(
  id: 'app:a',
  kind: CardKind.app,
  target: 'app:a',
  label: 'Alpha',
);

TvState _state() => TvState(
  cards: const [_card],
  config: LauncherConfig(layout: Layout.initial(['app:a'])),
  widgets: const [],
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
    await store.save(emptied.copyWith(contextMenu: const [CardAction.open]));
    expect(tv.sent, ['layout', 'options']);
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
    // The launcher's own home screen, drawing the TV's card: with no
    // picture, its name is on it as well as under it.
    expect(find.text('Alpha'), findsNWidgets(2));

    // A change made through the launcher's own controller reaches the TV.
    final layout = ref.read(configProvider).value!.layout;
    await ref
        .read(configProvider.notifier)
        .setLayout(layout.without({'app:a'}));
    await tester.pumpAndSettle();
    // Besides the screen asking how the Home button stands.
    expect(tv.sent.where((sent) => sent != 'homeButton'), ['layout']);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('a card pressed here is opened on the TV', (tester) async {
    final tv = _Tv()..answers['homeButton'] = {'enabled': true};
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
    expect(tv.sent, contains('open app:a'));
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
          cards: const [_card],
          config: LauncherConfig(layout: Layout.initial(['app:a'])),
          widgets: const [],
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

  test('what is asked of the device is asked of the TV', () async {
    final tv = _Tv();
    final platform = BrowserPlatform(tv);

    await platform.launchApp('app:a');
    await platform.switchToInput('input:tv/HW1');
    await platform.openAppInfo('app:a');
    await platform.uninstallApp('app:a');
    await platform.sendMediaCommand(MediaCommand.playPause);
    await platform.openHomeButtonSettings();
    expect(tv.sent, [
      'open app:a',
      'open input:tv/HW1',
      'info app:a',
      'uninstall app:a',
      'media {command: playPause}',
      'tvSettings',
    ]);

    expect(await platform.forceStopApp('app:a'), isFalse);
    tv.answers['forceStop'] = {'done': true};
    expect(await platform.forceStopApp('app:a'), isTrue);

    tv.answers['homeButton'] = {'enabled': true, 'canManage': false};
    expect(await platform.isHomeButtonEnabled(), isTrue);
    expect(await platform.canManageHomeButton(), isFalse);
    await platform.setHomeButtonEnabled(false);
    expect(tv.sent.last, 'homeButton {enabled: false}');

    tv.answers['setup'] = {'outcome': 'notAuthorised', 'detail': null};
    final result = await platform.runAutomaticSetup();
    expect(result.outcome, SetupOutcome.notAuthorised);
  });
}
