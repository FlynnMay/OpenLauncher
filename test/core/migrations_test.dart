import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/config/migrations/v2_to_v3.dart';
import 'package:openlauncher/core/config/migrations/v2_to_v3_panes.dart';
import 'package:openlauncher/core/config/migrations/v2_to_v3_slots.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

import '../support/packs.dart';

void main() {
  test('the release named in the code is the one in pubspec.yaml', () {
    final version = RegExp(
      r'^version:\s*(\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, version);
    // Plain X.Y.Z: the Android version code is worked out from it.
    expect(appVersion, matches(RegExp(r'^\d+\.\d{1,2}\.\d{1,2}$')));
  });

  test('a config is saved with its format and the release that wrote it', () {
    final written = LauncherConfig().toJson();
    expect((written['v'], written['app']), (saveVersion, appVersion));
    expect(LauncherConfig.fromJson(written).toJson(), written);
  });

  group('a save from a newer release', () {
    final newer = {
      'v': saveVersion + 1,
      'app': '9.0.0',
      'wallpapers': ['/w.png'],
      'layout': {'v': saveVersion + 1, 'layers': <Object?>[]},
    };

    test('is not read, and says which release wrote it', () {
      expect(isNewer(newer), isTrue);
      expect(
        () => migrate(newer),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('9.0.0'), contains(appVersion)),
          ),
        ),
      );
      // Not read in part either.
      expect(() => LauncherConfig.fromJson(newer), throwsFormatException);
      expect(
        () => migrate({'v': saveVersion + 1}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('newer'),
          ),
        ),
      );
    });

    test('nor is its layout sent on its own', () {
      expect(
        () => Layout.fromJson({'v': saveVersion + 1, 'layers': <Object?>[]}),
        throwsFormatException,
      );
    });
  });

  group('a step', () {
    final steps = [
      Migration(
        from: saveVersion,
        to: saveVersion + 1,
        since: '0.2.0',
        what: 'Wallpapers are called backdrops.',
        rules: [
          (save, device) => save['backdrops'] = save.remove('wallpapers'),
        ],
      ),
      Migration(
        from: saveVersion + 1,
        to: saveVersion + 2,
        since: '0.3.0',
        what: 'A layout names who made it.',
        rules: [(save, device) => (save['layout']! as Map)['by'] = 'me'],
      ),
    ];
    final old = {
      'v': saveVersion,
      'wallpapers': ['/w.png'],
      'layout': {'v': saveVersion, 'layers': <Object?>[]},
    };

    test('is run on an older save, in order, and the save restamped', () {
      final next = migrate(old, steps: steps);
      expect(next, {
        'v': saveVersion + 2,
        'backdrops': ['/w.png'],
        'layout': {'v': saveVersion + 2, 'layers': <Object?>[], 'by': 'me'},
      });
      // The save handed in is left as it was.
      expect(old['wallpapers'], ['/w.png']);
    });

    test('is not run on a save already past it', () {
      final later = {...old, 'v': saveVersion + 1, 'layout': null};
      expect(pending(later, steps: steps).map((step) => step.since), ['0.3.0']);
    });

    test('a current save is returned as it is', () {
      expect(migrate(old), same(old));
    });

    test('ends at the current format, each starting where the last ended', () {
      expect(migrations.first.from, 1);
      expect(migrations.last.to, saveVersion);
      for (final (index, step) in migrations.indexed.skip(1)) {
        expect(step.from, migrations[index - 1].to);
      }
    });
  });

  test('2 to 3: operations and machinery by address, feeds as sources', () {
    final next = migrate(
      {
        'v': 2,
        'entities': [
          {
            'id': 'mine',
            'actions': {
              'go': {
                'run': 'launchApp',
                'with': {'package': 'a'},
              },
              'dim': {'run': 'setVariable'},
              'odd': {'run': 'somethingElse'},
            },
            'feed': {'from': 'http', 'url': 'http://ha/x', 'every': 30},
          },
          {
            'id': 'now',
            'feed': {'from': 'clock'},
          },
        ],
        'layout': {
          'v': 2,
          'layers': [
            {
              'id': 'home',
              'root': {
                'id': 'root',
                'kind': 'pane',
                'on': {
                  'reveal': [
                    {'do': 'newLayer', 'entity': 'layers', 'dim': 0.5},
                    {'do': 'toLayer', 'entity': 'layers'},
                  ],
                  'press': [
                    {
                      'do': 'set',
                      'entity': 'variables',
                      'var': 'open',
                      'value': true,
                    },
                    {'do': 'remove', 'entity': 'home', 'what': 'app:a'},
                    {
                      'do': 'access',
                      'entity': 'system',
                      'access': 'homeButton',
                    },
                    {'do': 'open', 'entity': '{{source.id}}'},
                  ],
                },
              },
            },
          ],
        },
      },
      steps: [migrations[1]],
    );
    expect(next['v'], 3);
    final [mine, now] = next['entities']! as List;
    expect(mine['actions'], {
      'go': {
        'run': 'os://apps/launch',
        'with': {'package': 'a'},
      },
      'dim': {'run': 'launcher://variables/set'},
      'odd': {'run': 'somethingElse'},
    });
    expect(mine['feed'], {'url': 'http://ha/x', 'every': 30});
    expect(now['feed'], 'launcher://clock');
    // The rest of the step makes nodes of them: triggers are a module.
    final on =
        (next['layout']! as Map)['layers'][0]['root']['modules']['triggers'];
    expect(on['reveal'], [
      {
        'run': 'launcher://layers/new',
        'with': {'dim': 0.5},
      },
      {'run': 'launcher://layers/raise'},
    ]);
    expect(on['press'], [
      {
        'run': 'launcher://variables/set',
        'with': {'var': 'open', 'value': true},
      },
      {
        'run': 'launcher://layout/remove',
        'with': {'layer': 'home', 'what': 'system:app/a'},
      },
      {'do': 'access', 'entity': 'system:device', 'access': 'homeButton'},
      {'do': 'open', 'entity': '{{source.id}}'},
    ]);
  });

  test('2 to 3: what the launcher ships is named by the System pack', () {
    final next = migrate(
      {
        'v': 2,
        'names': {'app:a.b': 'Movies', 'mine': 'Mine'},
        'iconOverrides': {'input:hw1': 'p.png', 'folder:games': 'g.png'},
        'iconSources': {'app:a.b': 'input:hw1'},
        'entities': [
          {'id': 'mine', 'prefab': 'clock'},
        ],
        'prefabs': [
          {
            'id': 'weather',
            'name': 'My weather',
            'root': {
              'id': 'w',
              'kind': 'pane',
              'vars': {
                'source': {'value': 'weather', 'type': 'entity'},
              },
            },
          },
        ],
        'layout': {
          'v': 2,
          'removed': ['app:gone', 'mine'],
          'layers': [
            {
              'id': 'home',
              'root': {
                'id': 'root',
                'kind': 'pane',
                'options': {
                  'prefabRules': {
                    'app-card': {'variant': 'row'},
                    'mine': {'variant': 'x'},
                  },
                },
                'children': [
                  {
                    'id': 'settings',
                    'prefab': 'app-card',
                    'vars': {
                      'source': {
                        'value': 'launcher:settings',
                        'type': 'entity',
                      },
                    },
                  },
                  {
                    'id': 'note',
                    'kind': 'text',
                    'options': {
                      'text':
                          "{{clock.time}} {{media.playing ? 'clock' : mine.x}}",
                    },
                  },
                ],
              },
            },
          ],
        },
      },
      steps: [migrations[1]],
    );
    expect(next['names'], {'system:app/a.b': 'Movies', 'mine': 'Mine'});
    expect(next['iconOverrides'], {
      'system:input/hw1': 'p.png',
      'node:games': 'g.png',
    });
    expect(next['iconSources'], {'system:app/a.b': 'system:input/hw1'});
    expect((next['entities']! as List).single['prefab'], 'system:clock');
    final prefab = (next['prefabs']! as List).single as Map;
    // Their edit of the launcher's weather is still that weather, edited.
    expect(prefab['id'], 'system:weather');
    expect(
      prefab['root']['modules']['variables']['source']['value'],
      'system:weather',
    );
    final layout = next['layout']! as Map;
    expect(layout['removed'], ['system:app/gone', 'mine']);
    final root = layout['layers'][0]['root'] as Map;
    expect(root['modules']['prefabRules'], {
      'system:app-card': {'variant': 'row'},
      'mine': {'variant': 'x'},
    });
    final [card, note] = root['children'] as List;
    expect(card['prefab'], 'system:app-card');
    expect(card['modules']['variables']['source']['value'], 'system:settings');
    // Quoted text and the user's own are left as they are.
    expect(
      note['modules']['text']['text'],
      "{{system:clock.time}} {{system:media.playing ? 'clock' : mine.x}}",
    );
  });

  test('2 to 3: the quick actions are the System pack\'s prefab', () {
    final menu = {
      'id': 'quick-actions',
      'kind': 'pane',
      'options': {'dock': 'center', 'width': 500, 'rowHeight': 40},
      'style': {'borderWidth': 6},
      'children': [
        {'id': 'quick-actions-open', 'kind': 'button'},
      ],
    };
    final next = migrate({
      'v': 2,
      'layout': {
        'v': 2,
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'home/root',
              'kind': 'pane',
              'children': [
                {'id': 'main', 'kind': 'pane'},
                menu,
              ],
            },
          },
        ],
      },
    });
    final root = (next['layout']! as Map)['layers'][0]['root'] as Map;
    expect(root['children'], [
      {
        'id': 'main',
        'modules': {
          'layout': {'mode': 'flow'},
          'scroll': {'down': true},
          // The box the launcher gave it.
          'style': {'padding': 16, 'clip': true},
        },
      },
      // Its own look is kept; what it was made with is the prefab's.
      {
        'id': 'quick-actions',
        'prefab': 'system:quick-actions',
        'modules': {
          'dock': {'width': 500},
          'style': {'borderWidth': 6},
        },
      },
    ]);
  });

  test('2 to 3: folders and sidebars are the System pack\'s instances', () {
    final next = migrate({
      'v': 2,
      'layout': {
        'v': 2,
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'home/root',
              'kind': 'pane',
              'children': [
                {'id': 'main', 'kind': 'pane'},
                {
                  'id': 'games',
                  'kind': 'pane',
                  'options': {'dock': 'center'},
                },
                {
                  'id': 'left',
                  'kind': 'pane',
                  'options': {'dock': 'left', 'closed': 96},
                },
              ],
            },
          },
        ],
      },
    });
    final root = (next['layout']! as Map)['layers'][0]['root'] as Map;
    expect(
      [for (final Map pane in root['children']) pane['prefab']],
      [null, 'system:folder', 'system:sidebar'],
    );
  });

  test('2 to 3: a docked pane says whether a press closes it', () {
    Map pane(String id, Map options) => {
      'id': id,
      'kind': 'pane',
      'options': options,
    };
    final next = migrate({
      'v': 2,
      'layout': {
        'v': 2,
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'home/root',
              'kind': 'pane',
              'children': [
                {'id': 'main', 'kind': 'pane'},
                pane('games', {'dock': 'center'}),
                pane('near', {'dock': 'inline'}),
                pane('left', {'dock': 'left', 'closed': 96}),
              ],
            },
          },
        ],
      },
      'prefabs': [
        {
          'id': 'menu',
          'name': 'Menu',
          'root': pane('root', {'dock': 'center'}),
        },
      ],
    });
    // Drawn, the folder closes on a press as its prefab does; the one
    // opened in place and the sidebar do not.
    final layout = Layout.fromJson(next['layout']! as Map);
    final prefabs = {for (final prefab in systemPrefabs) prefab.id: prefab};
    expect(
      [
        for (final pane in layout.home.root.children)
          resolved(pane, prefabs).closeOnPress,
      ],
      [false, true, false, false],
    );
    final menu = (next['prefabs']! as List).single as Map;
    expect(menu['root']['modules']['dock']['closeOnPress'], isTrue);
  });

  group('2 to 3: nodes with modules', () {
    Json converted(Json layout, [List<Json> prefabs = const []]) {
      final save = <String, Object?>{'layout': layout, 'prefabs': prefabs};
      nodesAndModules(save, Device.unknown);
      return save;
    }

    Json home(Json root) => {
      'layers': [
        {'id': 'home', 'root': root},
      ],
    };

    List<dynamic> children(dynamic node) => node['children'] as List;

    test('a free pane\'s children sit where their cells were drawn', () {
      final save = converted(
        home({
          'id': 'home/root',
          'kind': 'pane',
          'options': {'mode': 'free', 'columns': 13},
          'children': [
            {
              'id': 'main',
              'kind': 'pane',
              'transform': {'w': 7, 'h': 5, 'x': 5, 'y': 3},
            },
            // No position: in a row below the rest.
            {
              'id': 'loose',
              'kind': 'text',
              'transform': {'w': 2},
            },
            // Docked, by itself or by its prefab: drawn by its layer.
            {
              'id': 'side',
              'kind': 'pane',
              'options': {'dock': 'right', 'closed': 64},
            },
            {'id': 'quick-actions', 'prefab': 'system:quick-actions'},
          ],
        }),
      );
      final root =
          ((save['layout']! as Json)['layers'] as List).single['root'] as Json;
      expect((root as Map).containsKey('modules'), isFalse);
      final [main, loose, side, menu] = children(root);
      // As the launcher drew it on cells: 13 columns over 960 pixels, gaps
      // of 20 across and 16 down, rows 1.45 times narrower than wide.
      const width = 960.0, columns = 13;
      const cell = (width - (columns - 1) * 20) / columns, row = cell / 1.45;
      Rect cells(double x, double y, double w, double h) => Rect.fromLTWH(
        x * (cell + 20),
        y * (row + 16),
        w * cell + (w - 1) * 20,
        h * row + (h - 1) * 16,
      );
      void at(dynamic node, Rect rect) {
        final drawn = NodeTransform.fromJson(node['transform'])
            .rectIn(const Size(width, 540));
        for (final (a, b) in [
          (drawn.left, rect.left),
          (drawn.top, rect.top),
          (drawn.right, rect.right),
          (drawn.bottom, rect.bottom),
        ]) {
          expect(a, closeTo(b, 0.1), reason: '${node['id']}');
        }
      }

      at(main, cells(5, 3, 7, 5));
      at(loose, cells(0, 8, 2, 1));
      // Across it keeps its share of any width.
      expect((main['transform'] as Json)['anchors'], [
        closeTo(5 / 13, 0.0001),
        0,
        closeTo(12 / 13, 0.0001),
        0,
      ]);
      expect(main['modules'], {
        'layout': {'mode': 'flow'},
        'scroll': {'down': true},
      });
      expect((side as Map).containsKey('transform'), isFalse);
      expect((menu as Map).containsKey('transform'), isFalse);
      expect(side['modules']['dock'], {'position': 'right', 'closed': 64});
    });

    test('what a pane said is in its modules', () {
      final save = converted(
        home({
          'id': 'root',
          'kind': 'pane',
          'options': {
            'title': 'Apps',
            'mode': 'grid',
            'columns': 4,
            'rowHeight': 40,
            'scrollX': true,
            'scrollbar': 'thumb',
            'scrollbarShow': 'auto',
            'prefabRules': {
              'system:app-card': {
                'variant': 'row',
                'overrides': {
                  'picture': {
                    'options': {'pad': 2},
                  },
                },
              },
            },
          },
          'style': {'background': '#000000', 'scrollbarSize': 8},
          'children': [
            {
              'id': 'card',
              'prefab': 'system:app-card',
              'transform': {'w': 2, 'x': 1, 'y': 0},
              'overrides': {
                'name': {
                  'hidden': true,
                  'style': {'fontSize': 20},
                  'transform': {'flex': 0},
                },
              },
            },
            for (final (mode, scroll) in [
              ('column', {'scrollY': true}),
              ('row', {'scrollX': true}),
              ('flow', {'scrollY': false}),
              ('row', <String, Object?>{}),
            ])
              {
                'id': 'in-$mode-${scroll.length}',
                'kind': 'pane',
                'options': {'mode': mode, ...scroll},
              },
          ],
        }),
      );
      final root =
          ((save['layout']! as Json)['layers'] as List).single['root'] as Json;
      expect(root['name'], 'Apps');
      expect(root['modules'], {
        'layout': {'mode': 'grid', 'columns': 4, 'rowHeight': 40},
        'prefabRules': {
          'system:app-card': {
            'variant': 'row',
            'overrides': {
              'picture': {
                'modules': {
                  'picture': {'pad': 2},
                },
              },
            },
          },
        },
        // Cells scrolled down unless told not to.
        'scroll': {
          'across': true,
          'down': true,
          'bar': 'thumb',
          'show': 'auto',
          'scrollbarSize': 8,
        },
        'style': {'background': '#000000'},
      });
      final [card, column, row, flow, still] = children(root);
      expect(card['modules'], {
        'sizing': {'w': 2, 'x': 1, 'y': 0},
      });
      expect(card['overrides'], {
        'name': {
          'modules': {
            'style': {'fontSize': 20},
            'sizing': {'flex': 0},
          },
          'hidden': true,
        },
      });
      expect(column['modules']['scroll'], {'down': true});
      expect(row['modules']['scroll'], {'across': true});
      expect(flow['modules'].containsKey('scroll'), isFalse);
      expect(still['modules'].containsKey('scroll'), isFalse);
    });

    test('what a node drew is its visual module; what is pressed takes the '
        'focus, shown where a part was framed', () {
      final save = converted(
        home({
          'id': 'root',
          'kind': 'pane',
          'children': [
            {
              'id': 'tile',
              'kind': 'pane',
              'options': {'mode': 'column'},
              'on': {
                'press': [
                  {'do': 'open', 'entity': '{{source.id}}'},
                ],
              },
              'children': [
                {
                  'id': 'art',
                  'kind': 'folder',
                  'options': {
                    'folder': '{{source.id}}',
                    'frame': true,
                    'bare': '{{source.bare}}',
                  },
                },
                {
                  'id': 'words',
                  'kind': 'text',
                  'options': {'text': 'Hi', 'overflow': 'wrap'},
                },
              ],
            },
            {
              'id': 'gauge',
              'kind': 'meter',
              'options': {'value': '{{clock.second}}', 'max': 60},
            },
            {
              'id': 'widget',
              'kind': 'android',
              'options': {'provider': 'a/b'},
            },
            {
              'id': 'go',
              'kind': 'button',
              'options': {'label': 'Open', 'icon': 'material:play_arrow'},
              'on': {
                'press': [
                  {'do': 'open', 'entity': 'system:app/a'},
                ],
              },
            },
            // A pane on cells never took the focus.
            {
              'id': 'cells',
              'kind': 'pane',
              'on': {
                'press': [
                  {'do': 'open', 'entity': 'system:app/a'},
                ],
              },
            },
          ],
        }),
      );
      final root =
          ((save['layout']! as Json)['layers'] as List).single['root'] as Json;
      final [tile, gauge, widget, go, cells] = children(root);
      expect(tile['modules']['focus'], {
        'target': 'art',
        'bare': '{{source.bare}}',
      });
      final [art, words] = children(tile);
      expect(art['modules'], {
        'preview': {'node': '{{source.id}}'},
      });
      expect(words['modules'], {
        'text': {'text': 'Hi', 'overflow': 'wrap'},
      });
      expect(gauge['modules'], {
        'meter': {'value': '{{clock.second}}', 'max': 60},
      });
      expect(widget['modules'], {
        'appWidget': {'provider': 'a/b'},
      });
      // A button is the System pack's, told its words.
      expect(go['prefab'], 'system:button');
      expect(go['modules']['variables'], {
        'label': 'Open',
        'icon': 'material:play_arrow',
      });
      expect(go['modules'].containsKey('focus'), isFalse);
      expect(cells['modules'].containsKey('focus'), isFalse);
    });

    test('how a pressed node showed its focus is written out', () {
      final press = {
        'press': [
          {'do': 'open', 'entity': 'system:app/a'},
        ],
      };
      final save = converted(
        home({
          'id': 'root',
          'kind': 'pane',
          'children': [
            {'id': 'leaf', 'kind': 'text', 'on': press},
            {
              'id': 'row',
              'kind': 'pane',
              'options': {'mode': 'row'},
              'on': press,
            },
            {
              'id': 'column',
              'kind': 'pane',
              'options': {'mode': 'column'},
              'style': {'padding': 4},
              'on': press,
            },
            {
              'id': 'framed',
              'kind': 'pane',
              'options': {'mode': 'column'},
              'on': press,
              'children': [
                {
                  'id': 'art',
                  'kind': 'picture',
                  'options': {'frame': true},
                },
              ],
            },
          ],
        }),
      );
      final root =
          ((save['layout']! as Json)['layers'] as List).single['root'] as Json;
      final [leaf, row, column, framed] = children(root);
      expect(leaf['modules']['focus'], {'scale': 103});
      expect(leaf['modules'].containsKey('style'), isFalse);
      expect(row['modules']['focus'], {'scale': 104});
      expect(row['modules']['style'], {'padding': 8});
      expect(column['modules']['focus'], isEmpty);
      expect(column['modules']['style'], {'padding': 4});
      expect(framed['modules']['focus'], {'target': 'art', 'bare': false});
    });

    test('a copy of a template is an instance holding what was in it', () {
      final card = {
        'id': 'tv',
        'prefab': 'system:app-card',
        'modules': {
          'variables': {
            'source': {'value': 'system:input/tv', 'type': 'entity'},
          },
        },
      };
      final save = <String, Object?>{
        'layout': home({
          'id': 'root',
          'children': [
            {
              'id': 'right',
              'template': 'system:sidebar',
              'modules': {
                'layout': {
                  'mode': 'grid',
                  'columns': 1,
                  'rowHeight': 16,
                  'itemW': 1,
                  'itemH': 1,
                },
                'prefabRules': {
                  'system:app-card': {'variant': 'row'},
                  'system:folder-card': {'variant': 'row'},
                },
                'dock': {'position': 'right', 'closed': 64},
                'scroll': {'down': true},
              },
              'children': [card],
            },
            // A user's own template is linked too, and becomes a prefab.
            {
              'id': 'shelf',
              'name': 'Games',
              'template': 'shelf',
              'modules': {
                'layout': {'mode': 'flow'},
                'dock': {'position': 'bottom'},
              },
            },
            // One whose template is gone stays a plain pane.
            {'id': 'lost', 'template': 'acme:gone'},
          ],
        }),
        'prefabs': [
          {
            'id': 'shelf',
            'name': 'Shelf',
            'template': true,
            'root': {
              'id': 'root',
              'modules': {
                'layout': {'mode': 'flow'},
                'dock': {'position': 'bottom'},
              },
            },
          },
        ],
      };
      templatesLinked(save, Device.unknown);
      final root =
          ((save['layout']! as Json)['layers'] as List).single['root'] as Json;
      final [right, shelf, lost] = children(root);
      // Nearest the variant down a side; only what differs is its own, and
      // where it docks always is. The chains it was made without stay unset.
      expect(right, {
        'id': 'right',
        'prefab': 'system:sidebar',
        'variant': 'side',
        'modules': {
          'layout': {'mode': 'grid', 'rowHeight': 16},
          'dock': {'position': 'right', 'closed': 64},
          'triggers': {
            'focus': null,
            'blur': null,
            'reveal': null,
            'hide': null,
          },
          'variables': {
            'content': [card],
          },
        },
      });
      expect(shelf, {
        'id': 'shelf',
        'name': 'Games',
        'prefab': 'shelf',
        'modules': {
          'dock': {'position': 'bottom'},
          'variables': {'content': <Object?>[]},
        },
      });
      expect(lost, {'id': 'lost'});
      final dynamic prefab = (save['prefabs']! as List).single;
      expect((prefab as Map).containsKey('template'), isFalse);
      expect(prefab['root']['modules']['slot'], {'variable': 'content'});
      expect(prefab['root']['modules']['variables'], {
        'content': {'value': null, 'type': 'nodes'},
      });
    });

    test('a prefab\'s variants are overrides of its own nodes', () {
      final save = converted(home({'id': 'root', 'kind': 'pane'}), [
        {
          'id': 'tile',
          'name': 'Tile',
          'root': {
            'id': 'root',
            'kind': 'pane',
            'transform': {'w': 2},
            'options': {'mode': 'row', 'fit': true},
            'children': [
              {
                'id': 'pic',
                'kind': 'picture',
                'options': {'fit': 'cover'},
              },
            ],
          },
          'variants': {
            'tight': {
              'label': 'Tight',
              'overrides': {
                'root': {
                  'options': {'fit': false, 'title': 'Small'},
                },
                'pic': {
                  'options': {'fit': 'contain'},
                },
              },
            },
          },
        },
      ]);
      final dynamic prefab = (save['prefabs']! as List).single;
      expect(prefab['root']['modules']['sizing'], {'w': 2});
      expect(prefab['root']['modules']['layout'], {'mode': 'row', 'fit': true});
      // The same key is a Layout's on a pane and a Picture's on a picture.
      expect(prefab['variants']['tight']['overrides'], {
        'root': {
          'modules': {
            'layout': {'fit': false},
          },
          'name': 'Small',
        },
        'pic': {
          'modules': {
            'picture': {'fit': 'contain'},
          },
        },
      });
    });
  });

  group('2 to 3: panes', () {
    Json save(List<Json> children, {List<Json> prefabs = const []}) => {
      'layout': {
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'home/root',
              'modules': {
                'layout': {'mode': 'grid'},
              },
              'children': children,
            },
          },
        ],
      },
      'prefabs': prefabs,
    };
    List<Object?> childrenOf(Json save) =>
        ((save['layout']! as Map)['layers'] as List)[0]['root']['children']
            as List;
    const card = {'id': 'a', 'prefab': 'system:app-card'};

    test('nothing docks inline, and a folder\'s picture is a node\'s', () {
      final folder = {
        'id': 'games',
        'modules': {
          'dock': {'position': 'inline', 'closeOnPress': true},
        },
      };
      final next = save([folder])
        ..['iconOverrides'] = {
          'folder:games': '/games.png',
          'system:app/a': '/a.png',
        };
      inlineDocksCentred(next, Device.unknown);
      expect(childrenOf(next).single, {
        'id': 'games',
        'modules': {
          'dock': {'position': 'center', 'closeOnPress': true},
        },
      });
      expect(next['iconOverrides'], {
        'node:games': '/games.png',
        'system:app/a': '/a.png',
      });
    });

    test('a pane writes out its box, and one with a heading is a Pane', () {
      final next = save(
        [
          {
            'id': 'apps',
            'name': 'Apps',
            'modules': {
              'layout': {'mode': 'grid', 'columns': 4},
              'sizing': {'w': 6, 'h': 2},
              'style': {'background': '#112233'},
            },
            'children': [card],
          },
          {
            'id': 'plain',
            'modules': {
              'layout': {'mode': 'flow'},
              'scroll': {'down': true},
              'style': {'padding': 4},
            },
          },
          {
            'id': 'line',
            'name': 'Line',
            'modules': {
              'layout': {'mode': 'row'},
            },
          },
          {
            'id': 'named',
            'name': '{{system:clock.time}}',
            'modules': {
              'layout': {'mode': 'flow'},
            },
          },
        ],
        prefabs: [
          {
            'id': 'mine',
            'root': {
              'id': 'root',
              'name': 'Mine',
              'modules': {
                'layout': {'mode': 'flow'},
              },
            },
          },
        ],
      );
      panelsWrittenOut(next, Device.unknown);
      final [apps, plain, line, named] = childrenOf(next);
      expect(apps, {
        'id': 'apps',
        'name': 'Apps',
        'prefab': 'system:pane',
        'overrides': {
          'content': {
            'modules': {
              'layout': {'mode': 'grid', 'columns': 4},
              // It did not scroll.
              'scroll': {'down': false},
            },
          },
        },
        'modules': {
          'sizing': {'w': 6, 'h': 2},
          'style': {'background': '#112233'},
          'variables': {
            'content': [card],
          },
        },
      });
      // Padded where it said nothing, cut off at its edges; rounded only
      // where it paints.
      expect((plain as Map)['modules']['style'], {'padding': 4, 'clip': true});
      expect((line as Map)['modules'].containsKey('style'), isFalse);
      // A name reading variables is read by the heading itself.
      expect((named as Map)['overrides']['heading'], {
        'modules': {
          'text': {'text': '{{system:clock.time}}'},
        },
      });
      // The layer's root is as it was; a prefab's root gets its box.
      final root =
          ((next['layout']! as Map)['layers'] as List)[0]['root'] as Map;
      expect(root['modules'], {
        'layout': {'mode': 'grid'},
      });
      final prefab = (next['prefabs']! as List).single as Map;
      expect(prefab['root']['modules']['style'], {'padding': 16, 'clip': true});

      // Drawn, the Pane lays out what it holds as the pane did.
      final drawn = resolved(Node.fromJson(apps as Json), systemPrefabMap);
      final [heading, content] = drawn.children;
      expect(heading.visual, textModule);
      expect((content.mode, content.columns), (PaneMode.grid, 4));
      expect(content.scrollsDown, isFalse);
      expect(content.children.single.id, 'a');
      expect(drawn.style['radius'], 14);
    });
  });

  test('1 to 2: force stop and automatic setup are taken out', () {
    Map<String, Object?> button(String id, List<Map<String, Object?>> acts) => {
      'id': id,
      'kind': 'button',
      'on': {'press': acts},
    };
    const source = '{{source.id}}';
    final save = {
      'v': 1,
      'entities': [
        {
          'id': 'mine',
          'actions': {
            'forceStop': {'run': 'launchApp'},
            'kill': {'run': 'forceStopApp'},
          },
        },
      ],
      'layout': {
        'v': 1,
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'root',
              'kind': 'pane',
              'children': [
                button('open', [
                  {'do': 'open', 'entity': source},
                ]),
                button('stop', [
                  {'do': 'forceStop', 'entity': source},
                ]),
                button('both', [
                  {'do': 'forceStop', 'entity': 'app:a'},
                  {'do': 'open', 'entity': 'app:a'},
                ]),
                button('setup', [
                  {'do': 'setup', 'entity': 'system'},
                ]),
                button('home', [
                  {'do': 'homeButton', 'entity': 'system', 'enabled': true},
                ]),
                // The user's own action of that name is left alone; one
                // that ran what is gone goes.
                button('own', [
                  {'do': 'forceStop', 'entity': 'mine'},
                ]),
                button('kill', [
                  {'do': 'kill', 'entity': 'mine'},
                ]),
                // Not a button: it stays, doing nothing on a press.
                {
                  'id': 'card',
                  'prefab': 'app-card',
                  'on': {
                    'press': [
                      {'do': 'forceStop', 'entity': source},
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
      'prefabs': [
        {
          'id': 'p',
          'name': 'P',
          'root': {
            'id': 'p',
            'kind': 'pane',
            'children': [
              button('stop', [
                {'do': 'forceStop', 'entity': source},
              ]),
            ],
          },
        },
      ],
    };
    final next = migrate(save, steps: [migrations.first]);
    expect(next['v'], 2);
    final root = (next['layout']! as Map)['layers'][0]['root'] as Map;
    expect(root['children'], [
      button('open', [
        {'do': 'open', 'entity': source},
      ]),
      button('both', [
        {'do': 'open', 'entity': 'app:a'},
      ]),
      button('home', [
        {'do': 'access', 'entity': 'system', 'access': 'homeButton'},
      ]),
      button('own', [
        {'do': 'forceStop', 'entity': 'mine'},
      ]),
      {
        'id': 'card',
        'prefab': 'app-card',
        'on': {'press': <Object?>[]},
      },
    ]);
    expect((next['prefabs']! as List)[0]['root']['children'], isEmpty);
    expect((next['entities']! as List)[0]['actions'], {
      'forceStop': {'run': 'launchApp'},
    });
  });
}
