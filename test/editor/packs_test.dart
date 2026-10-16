import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/tv/tv.dart';

import '../support/packs.dart';

const _mdi = Pack(
  id: 'mdi',
  name: 'Home icons',
  version: '7',
  author: 'Someone',
  bytes: 3 << 20,
  files: ['fonts/mdi.ttf', 'icons/mdi.json'],
);

final _mdiSet = IconSet.fromJson('mdi', {
  'name': 'Home icons',
  'font': 'mdi.ttf',
  'icons': {
    'lamp': [0xe001, -1, 'light'],
    'sofa': [0xe002],
  },
})!;

class _Tv extends TvApi {
  final removed = <String>[];

  @override
  Future<void> setLayout(Layout layout) async {}

  @override
  Future<void> setConfig(Map<String, Object?> changed) async {}

  @override
  Future<void> removePack(String id) async => removed.add(id);
}

void main() {
  testWidgets('an icon is chosen from the picker, or typed', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var values = <String, Object?>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          packsProvider.overrideWith((ref) async => const [materialPack, _mdi]),
          iconSetProvider.overrideWith(
            (ref, id) async => switch (id) {
              'material' => materialSet,
              'mdi' => _mdiSet,
              _ => null,
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: optionFields(
                  options: ComponentRegistry.icon.options,
                  values: values,
                  onChanged: (next) => setState(() => values = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final all = materialSet.icons.length;

    await tester.tap(find.byTooltip('Choose icon'));
    await tester.pumpAndSettle();
    expect(find.text('$all icons'), findsOneWidget);
    // The most used come first; the rest are built as they scroll in.
    expect(packIcon('material:search'), findsOneWidget);
    expect(packIcon('material:thunderstorm'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'No icon'))
          .onPressed,
      isNull,
    );

    // By what it shows, not only by its name.
    await tester.enterText(find.byType(TextField).last, 'lightning');
    await tester.pumpAndSettle();
    expect(packIcon('material:thunderstorm'), findsOneWidget);
    expect(packIcon('material:search'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'thunder');
    await tester.pumpAndSettle();
    await tester.tap(packIcon('material:thunderstorm'));
    await tester.pumpAndSettle();
    expect(values, {'icon': 'material:thunderstorm'});
    expect(find.text('material:thunderstorm'), findsOneWidget);
    // Shown on the button that opens the picker.
    expect(packIcon('material:thunderstorm'), findsOneWidget);

    // By category, and from another pack's set.
    await tester.tap(find.byTooltip('Choose icon'));
    await tester.pumpAndSettle();
    final category = materialSet.categories.indexOf('Audio & Video');
    final inIt = materialSet.search('', category: category).length;
    await tester.tap(find.text('Audio & Video'));
    await tester.pumpAndSettle();
    expect(find.text('$inIt of $all icons'), findsOneWidget);
    await tester.tap(find.text('Material Symbols'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home icons').last);
    await tester.pumpAndSettle();
    expect(find.text('2 icons'), findsOneWidget);
    // A set without categories has none to choose.
    expect(find.text('All'), findsNothing);
    await tester.tap(packIcon('mdi:lamp'));
    await tester.pumpAndSettle();
    expect(values, {'icon': 'mdi:lamp'});

    await tester.tap(find.byTooltip('Choose icon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No icon'));
    await tester.pumpAndSettle();
    expect(values, isEmpty);

    // A template is typed; it names no one icon to show.
    await tester.enterText(
      find.byType(TextField).first,
      '{{system:weather.sky}}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(values, {'icon': '{{system:weather.sky}}'});
    expect(find.byIcon(Icons.interests_outlined), findsOneWidget);
  });

  testWidgets('the pack manager lists the packs and removes one not in use', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tv = _Tv();
    final home = homeLayout(['system:app/a']);
    final using = home.withPane(
      home.home.root.id,
      (pane) => pane.copyWith(
        children: [
          ...pane.children,
          const Component(
            id: 'b',
            kind: 'button',
            options: {'label': 'Lamp', 'icon': 'mdi:lamp'},
          ),
        ],
      ),
    );
    var layout = using;
    late StateSetter redraw;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          redraw = setState;
          return ProviderScope(
            key: ValueKey(layout),
            overrides: [
              ...tvOverrides,
              tvApiProvider.overrideWithValue(tv),
              iconSetProvider.overrideWith(
                (ref, id) async => switch (id) {
                  'material' => materialSet,
                  'mdi' => _mdiSet,
                  _ => null,
                },
              ),
              tvStateProvider.overrideWith(
                (ref) => Stream.value(
                  TvState(
                    entities: const [
                      Entity(
                        id: 'system:app/a',
                        category: appCategory,
                        label: 'A',
                      ),
                    ],
                    config: LauncherConfig(layout: layout),
                    components: const [],
                    packs: const [materialPack, _mdi],
                  ),
                ),
              ),
            ],
            child: const MaterialApp(home: EditorScreen()),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Packs'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Version 1  ·  Google  ·  Apache-2.0  ·  '
        '${materialSet.icons.length} icons  ·  2.0 MB  ·  Built in',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Version 7  ·  Someone  ·  2 icons  ·  3.0 MB  ·  In use in 1 place',
      ),
      findsOneWidget,
    );
    // Neither can go: one is the launcher's, the other is drawn somewhere.
    expect(find.byTooltip('Remove'), findsNothing);

    redraw(() => layout = home);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Packs'));
    await tester.pumpAndSettle();
    expect(
      find.text('Version 7  ·  Someone  ·  2 icons  ·  3.0 MB'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove "Home icons"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(tv.removed, ['mdi']);
  });

  testWidgets('on a phone, media and packs share a menu', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(_Tv()),
          tvStateProvider.overrideWith(
            (ref) => Stream.value(
              TvState(
                entities: const [],
                config: LauncherConfig(layout: homeLayout()),
                components: const [],
                packs: const [materialPack],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Media and packs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packs'));
    await tester.pumpAndSettle();
    expect(find.text('Material Symbols'), findsOneWidget);
  });

  test(
    'the TV\'s packs arrive with its state, and their files by request',
    () async {
      final asked = <http.BaseRequest>[];
      final api = TvApi(
        client: MockClient.streaming((request, body) async {
          if (request.url.path == '/api/events') {
            final state = {
              'entities': [],
              'layout': homeLayout().toJson(),
              'config': <String, Object?>{},
              'components': [],
              'widgetProviders': [],
              'packs': [_mdi.toJson(), 'not a pack'],
            };
            return http.StreamedResponse(
              Stream.value(utf8.encode('data: ${jsonEncode(state)}\n\n')),
              200,
            );
          }
          asked.add(request);
          return request.method == 'DELETE' ||
                  request.url.path.endsWith('mdi.json')
              ? http.StreamedResponse(Stream.value(utf8.encode('{}')), 200)
              : http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
        }),
      );
      final pack = (await api.states().first).packs.single;
      expect(pack, _mdi);
      expect(utf8.decode((await api.packFile(pack, 'icons/mdi.json'))!), '{}');
      expect(await api.packFile(pack, 'icons/none.json'), isNull);
      expect(asked.first.url.path, '/api/packs/mdi/icons/mdi.json');
      await api.removePack('mdi');
      expect(
        (asked.last.method, '${asked.last.url}'.split('/api/').last),
        ('DELETE', 'packs?id=mdi'),
      );
    },
  );
}
