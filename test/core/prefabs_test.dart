import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';

import '../support/packs.dart';

void main() {
  final card = systemPrefabs.first;
  final prefabs = {for (final prefab in systemPrefabs) prefab.id: prefab};
  const plain = Component(
    id: 'a',
    prefab: cardPrefabId,
    vars: {'source': Variable('app:a', type: VarType.entity)},
  );

  /// The component [id] of [instance] as it is drawn.
  Component part(Component instance, String id, [Map<String, Prefab>? among]) =>
      resolved(
        instance,
        among ?? prefabs,
      ).all.firstWhere((part) => part.id == '${instance.id}/$id');

  test('a prefab is a saved component, written and read back as it was', () {
    final read = Prefab.fromJson(card.toJson())!;
    expect(read.toJson(), card.toJson());
    expect(read.variants.keys, ['stacked', 'row']);
    // It is made of components like any on the screen.
    expect(read.root.isPane, isTrue);
    expect(read.root.children.map((part) => (part.id, part.kind)), [
      ('picture', 'picture'),
      ('name', 'text'),
    ]);
    expect(
      Prefab.listFromJson([card.toJson(), card.toJson(), 7]),
      hasLength(1),
    );
    expect(Prefab.fromJson({'id': 'Not An Id'}), isNull);
    expect(Prefab.fromJson({'id': 'no-root'}), isNull);
  });

  test('an instance is its prefab until it says otherwise', () {
    final drawn = resolved(plain, prefabs);
    expect((drawn.id, drawn.isPane, drawn.mode), ('a', true, PaneMode.column));
    expect(part(plain, 'name').options['text'], '{{source.label}}');
    expect(drawn.all.every((part) => !part.hidden), isTrue);
    // Its variables and triggers are the prefab's, with its own over them.
    expect(drawn.handed.firstOrNull, 'app:a');
    // Each act names who does it: the entity it was handed, the variables.
    expect(drawn.on, {
      Trigger.press: [
        const Act('open', {'entity': '{{source.id}}'}),
      ],
      Trigger.hold: [
        const Act('launcher://variables/set', {
          'of': 'quick-actions',
          'var': 'source',
          'value': '{{source.id}}',
        }),
        const Act('launcher://variables/set', {
          'of': 'quick-actions',
          'var': 'open',
          'value': true,
        }),
      ],
    });
    // What is not an instance is itself.
    expect(resolved(drawn, prefabs), same(drawn));
  });

  test('what an instance sets is its own, value by value', () {
    final item = plain
        .withVariant('row')
        .copyWith(
          overrides: withOverride(
            withOverride(const {}, 'name', {'fontSize': 20}, 'style'),
            'picture',
            {'hidden': true},
          ),
          on: {Trigger.hold: const []},
        );
    final drawn = resolved(item, prefabs);
    expect(drawn.mode, PaneMode.row);
    // Its look is set over property by property: what the variant says of
    // the part still counts, and what the prefab does, under what it set.
    expect(part(item, 'name').style, {
      'fontSize': 20,
      'fontWeight': 'medium',
      'textAlign': 'left',
    });
    // The variant gives the picture a shape in place of a share.
    expect(
      (part(item, 'picture').flex, part(item, 'picture').aspect),
      (null, 16 / 9),
    );
    expect(part(item, 'picture').hidden, isTrue);
    expect(drawn.on[Trigger.hold], isEmpty);
    expect(drawn.on[Trigger.press], [
      const Act('open', {'entity': '{{source.id}}'}),
    ]);

    // The prefab changes: the instance follows, but for what it set.
    final changed = {
      ...prefabs,
      card.id: card.withPart(
        'name',
        (name) => name.copyWith(
          options: const {'text': 'App: {{source.label}}'},
          style: const {'fontSize': 30},
        ),
      ),
    };
    expect(
      part(item, 'name', changed).options['text'],
      'App: {{source.label}}',
    );
    expect(part(item, 'name', changed).style['fontSize'], 20);
    expect(part(plain, 'name', changed).style['fontSize'], 30);

    // A value handed back is the prefab's again.
    final back = item.copyWith(
      overrides: withOverride(item.overrides, 'name', {
        'fontSize': null,
      }, 'style'),
    );
    expect(part(back, 'name', changed).style['fontSize'], 30);
    expect(back.overrides.keys, ['picture']);
  });

  test("a pane's rule counts over what an instance says", () {
    final item = plain
        .withVariant('row')
        .copyWith(
          overrides: const {
            'name': {
              'hidden': true,
              'style': {'fontSize': 20},
            },
          },
        );
    final ruled = item.underRule(const {
      'variant': 'stacked',
      'overrides': {
        'name': {'hidden': false},
      },
    });
    expect(resolved(ruled, prefabs).mode, PaneMode.column);
    expect(part(ruled, 'name').hidden, isFalse);
    // What the rule says nothing of is still the instance's.
    expect(part(ruled, 'name').style['fontSize'], 20);
  });

  test('what opens a folder is an instance too', () {
    final folder = Component.of('games', id: 'f', prefab: folderPrefabId);
    expect(part(folder, 'picture').kind, 'folder');
    // What it does is set the `open` of whatever it was handed: said in
    // the prefab, against its `source`, like anything else.
    expect(resolved(folder, prefabs).on[Trigger.press], [
      const Act('launcher://variables/set', {
        'var': 'open',
        'value': true,
        'of': '{{source.id}}',
      }),
    ]);
    expect(folder.handed.firstOrNull, 'games');
  });

  test('a prefab can be made of panes, and of other prefabs', () {
    // The weather keeps its lines in a pane of their own.
    final weather = Component.of('weather', id: 'w', prefab: 'weather');
    final drawn = resolved(weather, prefabs);
    expect(drawn.children.map((part) => (part.id, part.isPane)), [
      ('w/icon', false),
      ('w/lines', true),
    ]);
    expect(part(weather, 'temperature').style['fontSize'], 38);
    // One made from another is that other, with what it sets over it.
    final own = Prefab(
      id: 'loud-card',
      name: 'Loud card',
      root: const Component(
        id: 'root',
        prefab: cardPrefabId,
        overrides: {
          'name': {
            'style': {'fontSize': 40},
          },
        },
      ),
    );
    final loud = Component.of('app:a', id: 'l', prefab: 'loud-card');
    final all = {...prefabs, own.id: own};
    expect(resolved(loud, all).on.keys, contains(Trigger.press));
    expect(resolved(loud, all).children.last.style['fontSize'], 40);
  });

  test('a card works out how its picture sits from the sort it was handed', () {
    Object? read(String template, Map<String, Object?> source) =>
        Template.parse(template).evaluate((root) => {'source': source}[root]);
    final picture = card.root.children.first.options;
    final small = card.variants['row']!.overrides['picture']!['options'] as Map;
    for (final (shape, fit, pad, tight, bare) in [
      ('banner', 'cover', 0, 0, false),
      ('icon', 'contain', 14, 4, false),
      ('line', 'contain', 0, 0, true),
      (null, 'contain', 0, 0, false),
    ]) {
      final source = {'shape': shape};
      expect(read(picture['fit']! as String, source), fit, reason: '$shape');
      expect(read(picture['pad']! as String, source), pad, reason: '$shape');
      expect(read(small['pad'] as String, source), tight, reason: '$shape');
      expect(read(picture['bare']! as String, source), bare, reason: '$shape');
    }
    // What the weather is like and who a song is by are worked out by
    // their prefabs too, from what the entities say.
    Object? told(String prefab, String name, Map<String, Object?> source) =>
        prefabs[prefab]!.vars[name]!.result(
          (template) => read(template, source),
        );
    expect(
      told('weather', 'summary', {
        'description': 'Sunny',
        'high': 24.6,
        'low': 9,
      }),
      'Sunny  ·  25° / 9°',
    );
    expect(told('weather', 'summary', {'description': 'Sunny'}), 'Sunny');
    expect(
      told('now-playing', 'summary', {'artist': 'Band', 'app': 'Player'}),
      'Band · Player',
    );
    expect(told('now-playing', 'summary', {'app': 'Player'}), 'Player');
  });

  test("the user's prefabs are settings like any other", () {
    final own = card.copyWith(id: 'big-entity', name: 'Big entity');
    final config = LauncherConfig().patched({
      'prefabs': [own.toJson(), 'nonsense'],
    });
    expect(config.prefabs.single.name, 'Big entity');
    expect(
      LauncherConfig.fromJson(config.toJson()).prefabs.single.toJson(),
      own.toJson(),
    );
  });
}
