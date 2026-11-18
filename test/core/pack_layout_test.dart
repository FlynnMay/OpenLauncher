import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/packs/pack_layout.dart';

void main() {
  group('a pack file', () {
    test('is a kind of thing in a feature folder', () {
      final flat = PackFile.of('weather/source.jsonc')!;
      expect(
        (flat.feature, flat.kind, flat.name),
        ('weather', PackKind.source, null),
      );
      final inFolder = PackFile.of('apps/prefab/card.json')!;
      expect(
        (inFolder.feature, inFolder.kind, inFolder.name),
        ('apps', PackKind.prefab, 'card'),
      );
    });

    test(
      'is not one of the folders with another purpose or an unknown kind',
      () {
        expect(PackFile.of('images/prefab.json'), isNull);
        expect(PackFile.of('icons/entity.json'), isNull);
        expect(PackFile.of('entities/lamp.json'), isNull);
        expect(PackFile.of('weather/notes.json'), isNull);
        expect(PackFile.of('source.json'), isNull);
      },
    );

    test('holds one object named for its folder, or several by name', () {
      final one = PackFile.of('weather/source.json')!;
      expect(
        one.items('weather/source.json', {'url': 'os://x'}).single.name,
        'weather',
      );
      final several = PackFile.of('weather/source.json')!
          .items('weather/source.json', {
            'a': {'url': 'os://a'},
            'b': {'url': 'os://b'},
          });
      expect([for (final item in several) item.name], ['a', 'b']);
      expect(several.last.where, 'weather/source.json#/b');
    });
  });

  group('a pack read by features', () {
    const pack = Pack(id: 'p', name: 'P');
    Map<String, String> files(Map<String, String> more) => more;

    test('names a source and a generator for their folder', () {
      final contents = PackContents.parse(
        pack,
        files({
          'lamp/source.json': '{"url": "os://lamps"}',
          'lamp/generator.json':
              '{"from": "lamp", "entity": {"id": "l/{{row.id}}"}}',
          'lamp/entity.json': '{"id": "lamp"}',
        }),
      );
      expect(contents.sources.keys, ['lamp']);
      expect(contents.generators.keys, ['lamp']);
      expect(contents.entities.single.id, 'p:lamp');
    });

    test('gives a card variable typed as a premade field its pack', () {
      final contents = PackContents.parse(
        const Pack(id: 'p', name: 'P', requires: ['other']),
        files({
          'lamp/prefab.json':
              '{"id": "lamp", "root": {"id": "root", "modules": {"variables": '
              '{"where": {"value": "", "type": "location"}, '
              '"unit": {"value": "", "type": "other:unit"}, '
              '"count": {"value": 1, "type": "number"}}}}}',
        }),
      );
      final vars = contents.prefabs.single.vars;
      expect(vars['where']!.field, 'p:location');
      expect(vars['unit']!.field, 'other:unit');
      expect(vars['count']!.type.name, 'number');
    });

    test('a field named like a variable type is used in full only', () {
      String prefab(String type) =>
          '{"id": "lamp", "root": {"id": "root", "modules": {"variables": '
          '{"accent": {"value": "", "type": "$type"}}}}}';
      final field = {'lamp/field/colour.json': '{"kind": "text"}'};
      final contents = PackContents.parse(
        pack,
        files({...field, 'lamp/prefab.json': prefab('p:colour')}),
      );
      expect(contents.prefabs.single.vars['accent']!.field, 'p:colour');
      expect(
        () => PackContents.parse(
          pack,
          files({...field, 'lamp/prefab.json': prefab('colour')}),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('writes the node part of an address in full and leaves the rest', () {
      final contents = PackContents.parse(
        pack,
        files({
          'lamp/entity.json': '{"id": "lamp"}',
          'lamp/prefab.json':
              '{"id": "card", "root": {"id": "root", "modules": {"variables": '
              '{"look": {"value": "{{lamp/icon#style.padding}}"}, '
              '"on": {"value": "{{lamp.on}}"}, '
              '"half": {"value": "{{lamp / 2}}"}}}}}',
        }),
      );
      final vars = contents.prefabs.single.vars;
      expect(vars['look']!.value, '{{p:lamp/icon#style.padding}}');
      expect(vars['on']!.value, '{{p:lamp.on}}');
      expect(vars['half']!.value, '{{p:lamp / 2}}');
    });

    test('refuses an id that is not a plain name, and a reserved variable', () {
      expect(
        () => PackContents.parse(
          pack,
          files({'lamp/entity.json': '{"id": "light.kitchen"}'}),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PackContents.parse(
          pack,
          files({
            'lamp/prefab.json':
                '{"id": "card", "root": {"id": "root", "modules": '
                '{"variables": {"parent": {"value": ""}}}}}',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('shares chunks from the feature folder, then the pack', () {
      final contents = PackContents.parse(
        pack,
        files({
          'defs.json': '{"\$defs": {"whole": {"label": "Pack"}, "local": {"label": "Pack"}}}',
          'lamp/defs.json': '{"\$defs": {"local": {"label": "Feature"}}}',
          'lamp/entity/a.json': '{"id": "a", "\$use": "local"}',
          'lamp/entity/b.json': '{"id": "b", "\$use": "whole"}',
          'other/entity.json': '{"id": "c", "\$use": "local"}',
        }),
      );
      final labels = {for (final e in contents.entities) e.id: e.label};
      expect(labels, {'p:a': 'Feature', 'p:b': 'Pack', 'p:c': 'Pack'});
    });

    test('refuses a second source of the same name', () {
      expect(
        () => PackContents.parse(
          pack,
          files({
            'lamp/source.json':
                '{"a": {"url": "os://a"}, "lamp": {"url": "os://b"}}',
            'lamp/source/lamp.json': '{"url": "os://c"}',
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('second "lamp"'),
          ),
        ),
      );
    });

    test('refuses the old layout, saying so', () {
      expect(
        () => PackContents.parse(
          pack,
          files({'entities/lamp.json': '{"id": "lamp"}'}),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('old pack layout'),
          ),
        ),
      );
    });
  });

  test(
    'a pack says the release it was written for, and still runs outside it',
    () {
      final pack = Pack.fromJson({'id': 'p', 'app': '0.2.0'})!;
      expect(pack.supportedBy('0.2.0'), isTrue);
      expect(pack.supportedBy('0.10.0'), isTrue);
      expect(pack.supportedBy('0.1.9'), isFalse);
      expect(Pack.fromJson({'id': 'q'})!.supportedBy('0.0.1'), isTrue);
    },
  );
}
