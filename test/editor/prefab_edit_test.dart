import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/editing/editing.dart';

import '../support/packs.dart';

void main() {
  final card = systemPrefabs.first;
  final prefabs = {for (final prefab in systemPrefabs) prefab.id: prefab};
  const text = Component(id: 'badge', kind: 'text', options: {'text': 'New'});

  /// [prefab] after [change] to it as a layout, shown as [variant].
  Prefab? edited(
    Prefab prefab,
    Layout Function(Layout layout) change, [
    String? variant,
  ]) => withEdited(
    prefab,
    variant,
    prefabRootIn(change(prefabAsLayout(prefab, variant)), prefab.root.id)!,
  );

  test('a prefab is edited as a layout of its root alone', () {
    final layout = prefabAsLayout(card);
    expect(layout.home.root.id, prefabStageId);
    expect(layout.home.root.children.single.toJson(), card.root.toJson());
    // Its parts are found like anything on the screen, and new ids are free
    // among them.
    final name = findItems(layout, {'name'}).single;
    expect(name.parent.id, 'root');
    expect(layout.itemIdFor('name'), 'name-2');

    final added = edited(
      card,
      (layout) => dropItem(layout, text, const Drop('root', before: 'name')),
    )!;
    expect(added.root.children.map((part) => part.id), [
      'picture',
      'badge',
      'name',
    ]);
    expect(added.variants.keys, card.variants.keys);
    // Without its root there is nothing to save.
    expect(prefabRootIn(removeItem(layout, 'root'), 'root'), isNull);
  });

  test('under a variant an edit is that variant\'s override', () {
    final row = edited(
      card,
      (layout) => changeItems(
        layout,
        {'name'},
        (item, _) => item.copyWith(
          hidden: true,
          style: withStyle(item.style, {'fontSize': 20}),
        ),
      ),
      'row',
    )!;
    // The tree and the other variant are as they were.
    expect(row.root.toJson(), card.root.toJson());
    expect(row.variants['stacked']!.overrides, isEmpty);
    final name = row.variants['row']!.overrides['name']!;
    expect(name['hidden'], true);
    expect(name['style'], {'textAlign': 'left', 'fontSize': 20});
    // What the variant already said is kept.
    expect(
      name['transform'],
      card.variants['row']!.overrides['name']!['transform'],
    );
    expect(
      row.variants['row']!.overrides['root'],
      card.variants['row']!.overrides['root'],
    );
    // And it draws as edited.
    final drawn = row.rootAs('row').children.last;
    expect((drawn.hidden, drawn.style['fontSize']), (true, 20));

    // Structure, variables and triggers are the tree's alone.
    expect(
      edited(
        card,
        (layout) => dropItem(layout, text, const Drop('root')),
        'row',
      ),
      isNull,
    );
    expect(
      edited(
        card,
        (layout) => changeItems(layout, {
          'root',
        }, (item, _) => item.copyWith(vars: const {'x': Variable(1)})),
        'row',
      ),
      isNull,
    );
  });

  test('the difference between two trees is overrides that make one of '
      'the other', () {
    for (final prefab in systemPrefabs) {
      for (final variant in prefab.variants.keys) {
        final as = prefab.rootAs(variant);
        final between = overridesBetween(prefab.root, as)!;
        expect(
          jsonEncode(withOverrides(prefab.root, between).toJson()),
          jsonEncode(as.toJson()),
          reason: '${prefab.id} $variant',
        );
      }
    }
  });

  test('renaming or removing a part takes what names it along', () {
    final own = [card];
    final layout = homeLayout().withPane(
      'main',
      (pane) => pane
          .withOption('prefabRules', {
            cardPrefabId: {
              'variant': 'row',
              'overrides': {
                'name': {'hidden': true},
              },
            },
          })
          .copyWith(
            children: const [
              Component(
                id: 'a',
                prefab: cardPrefabId,
                overrides: {
                  'name': {'hidden': true},
                  'picture': {
                    'options': {'pad': 2},
                  },
                },
              ),
              // Another prefab's part of the same name is left alone.
              Component(
                id: 'b',
                prefab: folderPrefabId,
                overrides: {
                  'name': {'hidden': true},
                },
              ),
            ],
          ),
    );
    final renamed = withPartRenamed(layout, own, card, 'name', 'title');
    final after = renamed.prefabs.single;
    expect(after.root.children.map((part) => part.id), ['picture', 'title']);
    expect(after.variants['row']!.overrides.keys, ['root', 'picture', 'title']);
    final main = renamed.layout.pane('main')!;
    expect(main.children.first.overrides.keys, ['title', 'picture']);
    expect(main.children.last.overrides.keys, ['name']);
    expect(
      overridesFromJson(main.prefabRules[cardPrefabId]!['overrides']).keys,
      ['title'],
    );
    expect(main.prefabRules[cardPrefabId]!['variant'], 'row');

    final dropped = withPartIds(layout, own, cardPrefabId, {'name': null});
    expect(dropped.prefabs.single.variants['row']!.overrides.keys, [
      'root',
      'picture',
    ]);
    final left = dropped.layout.pane('main')!;
    expect(left.children.first.overrides.keys, ['picture']);
    expect(left.prefabRules[cardPrefabId], {'variant': 'row'});
  });

  test('a prefab cannot hold itself, however deep', () {
    final inner = Prefab(
      id: 'inner',
      name: 'Inner',
      root: Component.pane(
        id: 'root',
        children: const [Component(id: 'card', prefab: cardPrefabId)],
      ),
    );
    final outer = Prefab(
      id: 'outer',
      name: 'Outer',
      root: Component.pane(
        id: 'root',
        children: const [Component(id: 'in', prefab: 'inner')],
      ),
    );
    final all = {...prefabs, 'inner': inner, 'outer': outer};
    expect(holdsPrefab('outer', cardPrefabId, all), isTrue);
    expect(holdsPrefab('outer', 'outer', all), isTrue);
    expect(holdsPrefab(cardPrefabId, 'outer', all), isFalse);
    expect(holdsPrefab('inner', 'outer', all), isFalse);
    expect(instancesOf('inner', homeLayout(), all.values), 1);
  });

  test('deleting a prefab unpacks its instances with the values they had', () {
    final tile = Prefab(
      id: 'tile',
      name: 'Tile',
      variants: const {
        'plain': PrefabVariant('Plain'),
        'loud': PrefabVariant('Loud', {
          'label': {
            'style': {'fontSize': 30},
          },
        }),
      },
      root: Component.pane(
        id: 'root',
        mode: PaneMode.column,
        vars: const {
          'source': Variable(null, type: VarType.entity),
          'tint': Variable('#ff0000ff', type: VarType.colour),
        },
        children: const [
          Component(
            id: 'label',
            kind: 'text',
            options: {'text': '{{source.label}}'},
          ),
        ],
      ),
    );
    final holder = Prefab(
      id: 'holder',
      name: 'Holder',
      root: Component.pane(
        id: 'root',
        children: const [Component(id: 'label', prefab: 'tile')],
      ),
    );
    final all = {...prefabs, 'tile': tile, 'holder': holder};
    final layout = homeLayout().withPane(
      'main',
      (pane) => pane
          .withOption('prefabRules', {
            'tile': {'variant': 'loud'},
          })
          .copyWith(
            children: [
              cardOf('system:app/a', id: 'a', prefab: 'tile', w: 2),
              const Component(
                id: 'b',
                prefab: 'tile',
                vars: {'tint': Variable('#00ff00ff')},
                overrides: {
                  'label': {
                    'options': {'text': 'Mine'},
                  },
                },
              ),
              // Something already called what a child would be.
              const Component(id: 'a-label', kind: 'text'),
            ],
          ),
    );
    final after = withoutPrefab(layout, [tile, holder], all, 'tile');
    expect((after.instances, after.blank), (3, 2));
    expect(after.prefabs.map((prefab) => prefab.id), ['holder']);
    final main = after.layout.pane('main')!;
    expect(main.prefabRules, isEmpty);
    final [a, b, _] = main.children;
    // A plain pane where it stood, at its size, holding what it was handed.
    expect(
      (a.isInstance, a.isPane, a.mode, a.w),
      (false, true, PaneMode.column, 2),
    );
    expect(a.handed, ['system:app/a']);
    expect(a.vars['tint']!.value, '#ff0000ff');
    // The pane's rule is baked in, and ids stay unique.
    expect(a.children.single.id, 'a-label-2');
    expect(a.children.single.style['fontSize'], 30);
    expect(a.children.single.options['text'], '{{source.label}}');
    // Its own values over the prefab's; what neither gave stays blank.
    expect(b.vars['tint']!.value, '#00ff00ff');
    expect(b.vars['source']!.value, isNull);
    expect(b.children.single.options['text'], 'Mine');
    expect(hasBlank(b), isTrue);
    expect(
      after.layout.all.map((part) => part.id).toSet().length,
      after.layout.all.length,
    );
    // Inside another prefab too, with ids free among that prefab's.
    final held = after.prefabs.single.root.children.single;
    expect((held.id, held.isInstance), ('label', false));
    expect(held.children.single.id, 'label-label');

    // One instance alone, the prefab kept.
    final one = withUnpacked(layout, 'b', all);
    expect(one.pane('main')!.children.map((item) => item.isInstance), [
      true,
      false,
      false,
    ]);
  });

  test('a component is made a prefab and an instance takes its place', () {
    final pane = Component.pane(
      id: 'weather-box',
      x: 2,
      y: 3,
      w: 4,
      h: 2,
      vars: const {'city': Variable('Perth')},
      children: const [Component(id: 'root', kind: 'text')],
    );
    final made = asPrefab(pane, 'box', 'Box');
    expect((made.prefab.id, made.prefab.name), ('box', 'Box'));
    // Its root has an id of its own among its parts, and no position.
    expect(made.prefab.root.id, 'root-2');
    expect((made.prefab.root.x, made.prefab.root.w), (null, 4));
    expect(made.prefab.root.vars.keys, ['city']);
    expect(made.instance.toJson(), {
      'id': 'weather-box',
      'prefab': 'box',
      'transform': {'w': 4, 'h': 2, 'x': 2, 'y': 3},
    });
    final drawn = resolved(made.instance, {'box': made.prefab});
    expect(drawn.children.single.id, 'weather-box/root');
    expect(drawn.vars['city']!.value, 'Perth');
  });

  test('a variable is exposed unless it says it is not', () {
    expect(Variable.fromJson('x').exposed, isTrue);
    expect(Variable.fromJson({'value': 'x', 'type': 'text'}).exposed, isTrue);
    const hidden = Variable('x', exposed: false);
    expect(hidden.toJson(), {'value': 'x', 'exposed': false});
    expect(Variable.fromJson(hidden.toJson()).exposed, isFalse);
    expect(const Variable('x').toJson(), 'x');
    // Through the editor's form and back.
    final form = variablesToForm(const {'a': hidden, 'b': Variable(1)});
    expect(form.map((one) => one['exposed']), [false, null]);
    final back = variablesFromForm(form);
    expect((back['a']!.exposed, back['b']!.exposed), (false, true));
    // The launcher's own computed ones are kept off instances.
    final weather = prefabs['system:weather']!.root.vars;
    expect(
      {for (final entry in weather.entries) entry.key: entry.value.exposed},
      {'source': true, 'icon': false, 'summary': false},
    );
  });
}
