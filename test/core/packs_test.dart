import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/features/components/pack_icon.dart';

import '../support/packs.dart';

void main() {
  group('an icon set', () {
    final set = IconSet.fromJson('mdi', {
      'name': 'Home icons',
      'font': 'mdi.ttf',
      'categories': ['Rooms', 'Lights'],
      'icons': {
        'sofa': [0xe001, 0, 'couch seat lamp'],
        'lamp': [0xe002, 1, 'light bulb'],
        'floor_lamp': [0xe003, 1, 'light'],
        'bare': [0xe004],
        'broken': 'no',
      },
    })!;

    test('is read from its index, in the order written', () {
      expect(set.name, 'Home icons');
      expect(set.icons.keys, ['sofa', 'lamp', 'floor_lamp', 'bare']);
      expect(set.icons['lamp'], (
        code: 0xe002,
        category: 1,
        words: 'light bulb',
      ));
      expect(set.icons['bare'], (code: 0xe004, category: -1, words: ''));
      expect(IconSet.fromJson('x', {'icons': {}}), isNull);
    });

    test('is searched by name first, then by what an icon shows', () {
      expect(set.search(''), ['sofa', 'lamp', 'floor_lamp', 'bare']);
      expect(set.search('lamp'), ['lamp', 'floor_lamp', 'sofa']);
      expect(set.search('floor lamp'), ['floor_lamp']);
      expect(set.search('Light'), ['lamp', 'floor_lamp']);
      expect(set.search('', category: 1), ['lamp', 'floor_lamp']);
      expect(set.search('lamp', category: 0), ['sofa']);
      expect(set.search('nothing'), isEmpty);
    });

    test('names its icons by set', () {
      expect(set.ref('lamp'), 'mdi:lamp');
      expect(iconRef('mdi:lamp'), (set: 'mdi', name: 'lamp'));
      for (final not in ['lamp', ':lamp', 'mdi:', '', null, 4]) {
        expect(iconRef(not), isNull);
      }
    });
  });

  group('the Material pack', () {
    test('has every icon the launcher itself names', () {
      final named = <String>{
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            for (final match in RegExp(
              "'material:([a-z0-9_]+)'",
            ).allMatches(file.readAsStringSync()))
              match[1]!,
      };
      expect(named, isNotEmpty);
      expect(named.difference(materialSet.icons.keys.toSet()), isEmpty);
    });

    test('has a category for every icon', () {
      expect(materialSet.icons.length, greaterThan(3000));
      for (final glyph in materialSet.icons.values) {
        expect(
          glyph.category,
          inInclusiveRange(0, materialSet.categories.length - 1),
        );
      }
    });
  });

  group('the pack store', () {
    late Directory tmp;
    late MemoryConfigStore config;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('openlauncher_packs');
      config = MemoryConfigStore();
      addTearDown(() => tmp.delete(recursive: true));
    });

    ProviderContainer container([Map<String, Uint8List> bundled = const {}]) {
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(config),
          packsDirProvider.overrideWith(
            (ref) => Directory('${tmp.path}/packs'),
          ),
          bundledPacksProvider.overrideWithValue(BundledPacks(bundled)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<PackRefused> refused(Future<Object?> doing) async {
      try {
        await doing;
      } on PackRefused catch (refusal) {
        return refusal;
      }
      fail('Not refused');
    }

    test(
      'unpacks the built-in packs once, and again when one changes',
      () async {
        final zip = packZip('core');
        var store = container({'core': zip}).read(packStoreProvider);
        final pack = (await store.list()).single;
        expect(pack.id, 'core');
        expect(pack.name, 'Pack core');
        expect(pack.builtIn, isTrue);
        expect(pack.iconSets, ['core']);
        expect(pack.bytes, greaterThan(0));
        final index = File('${tmp.path}/packs/core/icons/core.json');
        final unpacked = index.lastModifiedSync();

        // The same zip is left alone, by a later run too.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        store = container({'core': zip}).read(packStoreProvider);
        expect((await store.list()).single.version, '1');
        expect(index.lastModifiedSync(), unpacked);

        store = container({'core': packZip('core', version: '2')})
            .read(packStoreProvider);
        expect((await store.list()).single.version, '2');
      },
    );

    test('installs a pack from a zip, and reads its files', () async {
      final packs = container({'core': packZip('core')});
      final store = packs.read(packStoreProvider);
      expect((await packs.read(packsProvider.future)).length, 1);

      final pack = await store.install(Stream.value(packZip('mdi')));
      expect(pack.id, 'mdi');
      // Built-in first; whoever lists packs is told.
      final listed = await packs.read(packsProvider.future);
      expect(listed.map((pack) => pack.id), ['core', 'mdi']);
      expect(listed.last.builtIn, isFalse);

      final set = IconSet.fromJson(
        'mdi',
        jsonDecode(
          utf8.decode((await store.read(listed.last, 'icons/mdi.json'))!),
        ),
      )!;
      expect(set.icons.keys, ['lamp']);
      expect(await store.read(listed.last, 'fonts/mdi.ttf'), fontBytes);
      // Nothing outside what a pack holds.
      expect(await store.read(listed.last, '../core/pack.json'), isNull);
      expect(await store.read(listed.last, 'icons/none.json'), isNull);
      expect(await store.pathOf('../packs/mdi', 'pack.json'), isNull);

      // The same id again replaces it.
      await store.install(Stream.value(packZip('mdi', version: '9')));
      expect((await store.list()).last.version, '9');
    });

    test(
      'takes a zip of the pack\'s folder, and only the files it knows',
      () async {
        final store = container().read(packStoreProvider);
        await store.install(
          Stream.value(
            zipOf({
              'mdi-pack/pack.json': jsonEncode({'id': 'mdi'}),
              'mdi-pack/fonts/mdi.ttf': fontBytes,
              'mdi-pack/icons/mdi.json': jsonEncode({
                'font': 'mdi.ttf',
                'icons': {},
              }),
              'mdi-pack/README.md': 'hello',
              'mdi-pack/../../escaped.json': '{}',
              'mdi-pack/fonts/../../../escaped.ttf': fontBytes,
              'mdi-pack/scripts/later.js': 'run()',
            }),
          ),
        );
        final kept = [
          for (final file in tmp.listSync(recursive: true))
            if (file is File) file.path.substring(tmp.path.length),
        ]..sort();
        expect(kept, [
          '/packs/mdi/fonts/mdi.ttf',
          '/packs/mdi/icons/mdi.json',
          '/packs/mdi/pack.json',
        ]);
        // Named for its id when it gives no name.
        expect((await store.list()).single.name, 'mdi');
      },
    );

    test('turns down what is not a pack', () async {
      final store = container({'core': packZip('core')})
          .read(packStoreProvider);
      Future<PackRefused> install(Uint8List zip) =>
          refused(store.install(Stream.value(zip)));

      expect((await install(Uint8List.fromList([1, 2, 3]))).status, 415);
      expect((await install(zipOf({'readme.txt': 'hi'}))).status, 400);
      expect((await install(zipOf({'pack.json': 'not json'}))).status, 400);
      expect(
        (await install(
          zipOf({
            'pack.json': jsonEncode({'id': 'Bad Id'}),
          }),
        )).status,
        400,
      );
      // Not a font.
      expect(
        (await install(
          zipOf({
            'pack.json': jsonEncode({'id': 'x'}),
            'fonts/x.ttf': 'MZ not a font',
          }),
        )).status,
        415,
      );
      // An icon set whose font did not come with it.
      expect(
        (await install(
          zipOf({
            'pack.json': jsonEncode({'id': 'x'}),
            'icons/x.json': jsonEncode({'font': 'x.ttf', 'icons': {}}),
          }),
        )).status,
        400,
      );
      // Icons called what another pack's are.
      expect(
        (await install(
          zipOf({
            'pack.json': jsonEncode({'id': 'x'}),
            'fonts/x.ttf': fontBytes,
            'icons/core.json': jsonEncode({'font': 'x.ttf', 'icons': {}}),
          }),
        )).message,
        'Another pack already has icons called "core"',
      );
      // A built-in pack is not replaced.
      expect((await install(packZip('core', version: '6'))).status, 409);
      final too = await refused(
        store.install(
          Stream.fromIterable([
            for (var i = 0; i <= PackStore.maxZipBytes >> 20; i++)
              Uint8List(1 << 20),
          ]),
        ),
      );
      expect(too.status, 413);

      final only = (await store.list()).single;
      expect((only.id, only.version), ('core', '1'));
      expect(Directory('${tmp.path}/packs').listSync().length, 1);
    });

    test('removes a pack unless it is built in or in use', () async {
      final packs = container({'core': packZip('core')});
      final store = packs.read(packStoreProvider);
      await store.install(Stream.value(packZip('mdi')));
      final home = (await packs.read(configProvider.future)).layout;
      await packs
          .read(configProvider.notifier)
          .setLayout(
            home.withPane(
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
            ),
          );

      expect((await refused(store.delete('none'))).status, 404);
      expect(
        (await refused(store.delete('core'))).message,
        '"Pack core" is built in',
      );
      expect(
        (await refused(store.delete('mdi'))).message,
        '"Pack mdi" is in use: 1 icon',
      );

      await packs.read(configProvider.notifier).setLayout(home);
      await store.delete('mdi');
      expect((await packs.read(packsProvider.future)).map((pack) => pack.id), [
        'core',
      ]);
      expect(Directory('${tmp.path}/packs/mdi').existsSync(), isFalse);
    });
  });

  testWidgets('a pack icon is drawn from its set\'s font, by its saved name', (
    tester,
  ) async {
    final loaded = materialSet.loadedAs('pack/material');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iconSetProvider.overrideWith(
            (ref, id) async => id == 'material' ? loaded : null,
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              PackIcon('material:home', size: 40, color: Colors.red),
              PackIcon('material:no_such_icon', size: 40),
              PackIcon('other:home'),
              PackIcon('home'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final glyph = tester.widget<Text>(find.byType(Text));
    expect(glyph.data, String.fromCharCode(materialSet.icons['home']!.code));
    expect(glyph.style!.fontFamily, 'pack/material');
    expect(glyph.style!.fontSize, 40);
    expect(glyph.style!.color, Colors.red);
    // The others keep their room and draw nothing.
    expect(
      tester.getSize(packIcon('material:no_such_icon')),
      const Size(40, 40),
    );
    expect(tester.getSize(packIcon('home')), const Size(24, 24));
  });
}
