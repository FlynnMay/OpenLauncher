import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_link.dart';

class _Tv extends TvApi {
  final sent = <String>[];

  @override
  Future<void> setLayout(Layout layout) async => sent.add('layout');

  @override
  Future<void> setOptions(LauncherConfig config) async => sent.add('options');
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
    expect(tv.sent, ['layout']);
    expect(find.text('Alpha'), findsNothing);
  });
}
