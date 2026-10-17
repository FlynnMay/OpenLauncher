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
  final plain = cardOf('system:app/a', id: 'a');

  /// The component [id] of [instance] as it is drawn.
  Node part(Node instance, String id, [Map<String, Prefab>? among]) => resolved(
    instance,
    among ?? prefabs,
  ).all.firstWhere((part) => part.id == '${instance.id}/$id');

  test('a prefab is a saved component, written and read back as it was', () {
    final read = Prefab.fromJson(card.toJson())!;
    expect(read.toJson(), card.toJson());
    expect(read.variants.keys, ['stacked', 'row']);
    // It is made of components like any on the screen.
    expect(read.root.isContainer, isTrue);
    expect(read.root.children.map((part) => (part.id, part.visual?.name)), [
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

  test(
    'an entity is handed to the first entity variable, whatever its name',
    () {
      final tile = Prefab(
        id: 'acme:tile',
        name: 'Tile',
        root: Node.layout(
          id: 'root',
          w: 2,
          vars: const {
            'title': Variable('Hi'),
            'thing': Variable(null, type: VarType.entity),
          },
        ),
      );
      expect(tile.entityVar, 'thing');
      final item = tile.instance('system:clock', id: 'c')!;
      expect((item.prefab, item.w), ('acme:tile', 2.0));
      expect(item.handed, ['system:clock']);
      expect(item.vars.keys, ['thing']);
      // One that takes no entity cannot show one.
      expect(
        Prefab(
          id: 'x',
          name: 'X',
          root: Node.layout(id: 'root'),
        ).instance('system:clock', id: 'c'),
        isNull,
      );
    },
  );

  test('an instance is its prefab until it says otherwise', () {
    final drawn = resolved(plain, prefabs);
    expect(
      (drawn.id, drawn.isContainer, drawn.mode),
      ('a', true, LayoutMode.column),
    );
    expect(part(plain, 'name').values('text')?['text'], '{{source.label}}');
    expect(drawn.all.every((part) => !part.hidden), isTrue);
    // Its variables and triggers are the prefab's, with its own over them.
    expect(drawn.handed.firstOrNull, 'system:app/a');
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
        )
        .triggered({Trigger.hold: const []});
    final drawn = resolved(item, prefabs);
    expect(drawn.mode, LayoutMode.row);
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
        (name) => name
            .withModule('text', const {'text': 'App: {{source.label}}'})
            .styled(const {'fontSize': 30}),
      ),
    };
    expect(
      part(item, 'name', changed).values('text')?['text'],
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

  test("a container's rule counts over what an instance says", () {
    final item = plain
        .withVariant('row')
        .copyWith(
          overrides: const {
            'name': {
              'hidden': true,
              'modules': {
                'style': {'fontSize': 20},
              },
            },
          },
        );
    final ruled = item.underRule(const {
      'variant': 'stacked',
      'overrides': {
        'name': {'hidden': false},
      },
    });
    expect(resolved(ruled, prefabs).mode, LayoutMode.column);
    expect(part(ruled, 'name').hidden, isFalse);
    // What the rule says nothing of is still the instance's.
    expect(part(ruled, 'name').style['fontSize'], 20);
  });

  test('what opens a folder is an instance too', () {
    final folder = cardOf('games', id: 'f', prefab: folderPrefabId);
    expect(part(folder, 'picture').visual, previewModule);
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

  test('a prefab can be made of containers, and of other prefabs', () {
    // The weather keeps its lines in a container of their own.
    final weather = cardOf('system:weather', id: 'w', prefab: 'system:weather');
    final drawn = resolved(weather, prefabs);
    expect(drawn.children.map((part) => (part.id, part.isContainer)), [
      ('w/icon', false),
      ('w/lines', true),
    ]);
    expect(part(weather, 'temperature').style['fontSize'], 38);
    // One made from another is that other, with what it sets over it.
    final own = Prefab(
      id: 'loud-card',
      name: 'Loud card',
      root: const Node(
        id: 'root',
        prefab: cardPrefabId,
        overrides: {
          'name': {
            'modules': {
              'style': {'fontSize': 40},
            },
          },
        },
      ),
    );
    final loud = cardOf('system:app/a', id: 'l', prefab: 'loud-card');
    final all = {...prefabs, own.id: own};
    expect(resolved(loud, all).on.keys, contains(Trigger.press));
    expect(resolved(loud, all).children.last.style['fontSize'], 40);
  });

  test('an instance puts its own nodes in its prefab\'s slot', () {
    // A box with a heading, and a slot after it.
    final boxed = Prefab(
      id: 'boxed',
      name: 'Boxed',
      root: Node(
        id: 'root',
        modules: {
          layoutModule.name: const {'mode': 'column'},
          variablesModule.name: variablesToJson(const {
            'content': Variable(null, type: VarType.nodes),
          }),
        },
        children: const [
          Node(
            id: 'heading',
            modules: {
              'text': {'text': 'Hello'},
            },
          ),
          Node(
            id: 'body',
            modules: {
              'layout': {'mode': 'flow'},
              'slot': {'variable': 'content'},
            },
            children: [
              Node(
                id: 'first',
                modules: {
                  'text': {'text': 'Always'},
                },
              ),
            ],
          ),
        ],
      ),
    );
    final saved = {
      'id': 'mine',
      'prefab': 'boxed',
      'modules': {
        'variables': {
          'content': [plain.toJson(), cardOf('system:app/b', id: 'b').toJson()],
        },
      },
    };
    final instance = Node.fromJson(saved);
    // Held under the instance while in memory, saved as its variable.
    expect(instance.children.single.id, 'mine#content');
    expect(instance.vars, isEmpty);
    expect(instance.toJson(), saved);
    expect(instance.all.map((node) => node.id), [
      'mine',
      'mine#content',
      'a',
      'b',
    ]);
    // A layout sees them, and can change them.
    final layout = Layout(
      inbox: 'home/root',
      layers: [
        Layer(
          id: Layout.homeId,
          root: Node.layout(id: 'home/root', children: [instance]),
        ),
      ],
    );
    expect(layout.items.map((item) => item.id), containsAll(['a', 'b']));
    final fewer = layout.without({'system:app/b'});
    expect(fewer.items.map((item) => item.id), isNot(contains('b')));
    // Drawn after the slot's own children, with their own ids.
    final drawn = resolved(instance, {...prefabs, 'boxed': boxed});
    final body = drawn.children.last;
    expect(body.id, 'mine/body');
    expect(body.children.map((node) => node.id), ['mine/first', 'a', 'b']);
    expect(body.slotHolder, 'mine#content');
  });

  test('a card works out how its picture sits from the sort it was handed', () {
    Object? read(String template, Map<String, Object?> source) =>
        Template.parse(template).evaluate((root) => {'source': source}[root]);
    final picture = card.root.children.first.values('picture')!;
    final focus = card.root.values('focus')!;
    final small =
        (card.variants['row']!.overrides['picture']!['modules']!
                as Map)['picture']
            as Map;
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
      expect(read(focus['bare']! as String, source), bare, reason: '$shape');
    }
    // What the weather is like and who a song is by are worked out by
    // their prefabs too, from what the entities say.
    Object? told(String prefab, String name, Map<String, Object?> source) =>
        prefabs[prefab]!.vars[name]!.result(
          (template) => read(template, source),
        );
    expect(
      told('system:weather', 'summary', {
        'description': 'Sunny',
        'high': 24.6,
        'low': 9,
      }),
      'Sunny  ·  25° / 9°',
    );
    expect(
      told('system:weather', 'summary', {'description': 'Sunny'}),
      'Sunny',
    );
    expect(
      told('system:now-playing', 'summary', {
        'artist': 'Band',
        'app': 'Player',
      }),
      'Band · Player',
    );
    expect(told('system:now-playing', 'summary', {'app': 'Player'}), 'Player');
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
