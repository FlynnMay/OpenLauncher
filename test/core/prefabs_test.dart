import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';

void main() {
  final card = builtInPrefabs.first;
  final prefabs = {for (final prefab in builtInPrefabs) prefab.id: prefab};
  const plain = Component(
    id: 'a',
    prefab: cardPrefabId,
    vars: {'source': Variable('app:a')},
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
    expect(drawn.source, 'app:a');
    expect(drawn.on, {
      Trigger.press: [const Act('open')],
      Trigger.hold: [const Act('menu')],
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
    expect(drawn.on[Trigger.press], [const Act('open')]);

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
      const Act('set', {'var': 'open', 'value': true, 'of': '{{source.id}}'}),
    ]);
    expect(folder.source, 'games');
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

  group('a save from before everything was a component', () {
    // As version 14 wrote it.
    Map<String, Object?> old() => jsonDecode(
      jsonEncode({
        'v': 14,
        'wallpapers': ['/w.png'],
        'layout': {
          'v': 14,
          'inbox': 'pane',
          'removed': ['app:gone'],
          'panels': [
            {
              'id': 'home',
              'title': '',
              'pane': {
                'id': 'home/root',
                'title': '',
                'mode': 'free',
                'columns': 13,
                'items': [
                  {
                    'id': 'pane',
                    'kind': 'pane',
                    'ref': 'pane',
                    'w': 6.5,
                    'h': 3,
                    'x': 0.5,
                    'y': 1,
                    'pane': {
                      'id': 'pane',
                      'title': 'Inputs',
                      'mode': 'flow',
                      'columns': 5,
                      'rules': {'spacing': 14},
                      'prefabRules': {
                        'app-card': {
                          'layout': 'row',
                          'parts': {
                            'name': {'hidden': false},
                          },
                        },
                      },
                      'vars': {'room': 'Lounge'},
                      'style': {'background': '#101820cc'},
                      'items': [
                        {
                          'id': 'tv',
                          'kind': 'prefab',
                          'ref': 'app-card',
                          'w': 1,
                          'h': 1,
                          'vars': {'source': 'input:tv'},
                          'options': {
                            'layout': 'stacked',
                            'parts': {
                              'name': {
                                'hidden': true,
                                'overflow': 'fade',
                                'style': {'fontSize': 20},
                              },
                            },
                          },
                          'on': {
                            'hold': [
                              {'do': 'info'},
                            ],
                          },
                        },
                        {
                          'id': 'label',
                          'kind': 'component',
                          'ref': 'text',
                          'w': 2,
                          'h': 1,
                          'options': {'text': '{{clock.time}}'},
                          'style': {'fontSize': 30},
                        },
                      ],
                    },
                  },
                ],
              },
            },
            {
              'id': 'left',
              'title': '',
              'rules': {'closed': 64},
              'pane': {
                'id': 'left/root',
                'title': '',
                'mode': 'flow',
                'columns': 1,
                'items': <Object?>[],
              },
            },
          ],
        },
        'prefabs': [
          {
            'id': 'mine',
            'name': 'Mine',
            'w': 2,
            'vars': {'source': 'clock'},
            'on': {
              'press': [
                {'do': 'settings'},
              ],
            },
            'style': {'color': '#ff0000'},
            'parts': {
              'big': {
                'kind': 'text',
                'text': '{{source.time}}',
                'style': {'fontSize': 44},
              },
              'small': {'kind': 'text', 'text': '{{source.date}}'},
            },
            'layouts': {
              'stacked': {
                'label': 'One over the other',
                'direction': 'column',
                'gap': 4,
                'parts': [
                  {'part': 'big', 'flex': 1},
                  {
                    'group': {
                      'label': '',
                      'direction': 'row',
                      'gap': 0,
                      'parts': [
                        {'part': 'small', 'keep': true},
                      ],
                    },
                  },
                ],
              },
              'row': {
                'label': 'Side by side',
                'direction': 'row',
                'gap': 8,
                'parts': [
                  {
                    'part': 'big',
                    'aspect': 2,
                    'options': {
                      'style': {'textAlign': 'left'},
                    },
                  },
                  {'part': 'small', 'flex': 1},
                ],
              },
            },
          },
        ],
      }),
    ) as Map<String, Object?>;

    test('is brought up to date: a pane is a component', () {
      final config = LauncherConfig.fromJson(old());
      expect(config.wallpapers, ['/w.png']);
      final layout = config.layout;
      expect(layout.inbox, 'pane');
      expect(layout.removed, {'app:gone'});
      final root = layout.home.root;
      expect(
        (root.id, root.mode, root.columns),
        ('home/root', PaneMode.free, 13),
      );
      // What said where a pane was is gone: the pane says so itself.
      final pane = root.children.single;
      expect((pane.id, pane.isPane, pane.title), ('pane', true, 'Inputs'));
      expect((pane.x, pane.y, pane.w, pane.h), (0.5, 1, 6.5, 3));
      expect((pane.spacing, pane.columns), (14, 5));
      expect(pane.style, {'background': '#101820cc'});
      expect(pane.vars['room']?.value, 'Lounge');
      expect(pane.prefabRules, {
        'app-card': {
          'variant': 'row',
          'overrides': {
            'name': {'hidden': false},
          },
        },
      });

      final [tv, label] = pane.children;
      expect(
        (tv.prefab, tv.variant, tv.source),
        ('app-card', 'stacked', 'input:tv'),
      );
      expect(tv.overrides, {
        'name': {
          'hidden': true,
          'style': {'fontSize': 20},
          'options': {'overflow': 'fade'},
        },
      });
      expect(tv.options, isEmpty);
      expect(tv.on[Trigger.hold], [const Act('info')]);
      expect((label.kind, label.w), ('text', 2));
      expect(label.options, {'text': '{{clock.time}}'});
      expect(label.style, {'fontSize': 30});
      expect(layout.panel('left')!.closed, 64);
      expect(layout.panel('left')!.root.id, 'left/root');

      // And it is written as it now is, to be read as that from here on.
      final written = config.toJson();
      expect(versionOf(written), saveVersion);
      expect(LauncherConfig.fromJson(written).toJson(), written);
    });

    test('is brought up to date: a prefab is a component', () {
      final mine = LauncherConfig.fromJson(old()).prefabs.single;
      final root = mine.root;
      expect((root.mode, root.gap, root.w), (PaneMode.column, 4, 2));
      expect(root.source, 'clock');
      expect(root.on[Trigger.press], [const Act('settings')]);
      expect(root.style, {'color': '#ff0000'});
      // As its first layout had it, a group being a pane of its own.
      final [big, group] = root.children;
      expect((big.id, big.kind, big.flex), ('big', 'text', 1));
      expect(big.options, {'text': '{{source.time}}'});
      expect(big.style, {'fontSize': 44});
      expect((group.isPane, group.mode), (true, PaneMode.row));
      expect(group.children.single.keep, isTrue);
      // The other layout is a variant: what it sets differently.
      expect(mine.variants.keys, ['stacked', 'row']);
      expect(mine.variants['row']!.label, 'Side by side');
      final all = {mine.id: mine};
      final item = const Component(id: 'i', prefab: 'mine').withVariant('row');
      final drawn = resolved(item, all);
      expect((drawn.mode, drawn.gap), (PaneMode.row, 8));
      final [wide, _] = drawn.children;
      expect((wide.flex, wide.aspect), (null, 2));
      expect(wide.style, {'fontSize': 44, 'textAlign': 'left'});
      final small = drawn.all.firstWhere((part) => part.id == 'i/small');
      expect((small.flex, small.keep), (1, false));
    });

    test('from before the oldest step there is, it is not read', () {
      expect(
        () => migrate({'v': 9, 'layout': <String, Object?>{}}),
        throwsFormatException,
      );
      // The rest of such a config is still read.
      final config = LauncherConfig.fromJson({
        'v': 9,
        'layout': {'v': 9, 'panels': <Object?>[]},
        'wallpapers': ['/w.png'],
      });
      expect(config.wallpapers, ['/w.png']);
      expect(config.layout.home.root.children, hasLength(1));
    });
  });
}
