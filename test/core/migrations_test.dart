import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

Json _item(String id, String ref, [String kind = 'card']) => {
  'id': id,
  'kind': kind,
  'ref': ref,
};

/// A config as version 2 wrote it, ids and all.
Json _v2() => {
  'iconOverrides': {'panel:pq1w2e3r': '/games.png', 'app:a': '/a.png'},
  'layout': {
    'v': 2,
    'inbox': 'sabcdefg',
    'removed': ['app:gone'],
    'panels': [
      {
        'id': 'home',
        'pane': {
          'id': 'home/root',
          'mode': 'free',
          'items': [
            {
              ..._item('i1234567', 'sabcdefg', 'pane'),
              'w': 4,
              'pane': {
                'id': 'sabcdefg',
                'title': 'Inputs',
                'items': [
                  _item('io9lf5rv', 'input:x/HW15'),
                  _item('ixqv88j5', 'input:x/HW16'),
                  _item(
                    'auto:app:io.gh.reisxd.tizentube.cobalt',
                    'app:io.gh.reisxd.tizentube.cobalt',
                  ),
                  _item('mine', 'app:kept'),
                ],
              },
            },
            _item('ibxpqhuz', 'media', 'widget'),
            _item('iwidget1', 'android', 'widget'),
            _item('ifolder1', 'pq1w2e3r', 'panel'),
          ],
        },
      },
      {
        'id': 'left',
        'pane': {'id': 'left/root', 'columns': 3},
      },
      {
        'id': 'pq1w2e3r',
        'title': 'Games',
        'pane': {'id': 'pq1w2e3r/root'},
      },
    ],
  },
};

void main() {
  test('the steps lead from the first version to this one, one at a time', () {
    expect(migrations.first.from, 1);
    expect(migrations.last.to, saveVersion);
    for (final (index, step) in migrations.indexed) {
      expect(step.to, step.from + 1, reason: step.what);
      expect(step.from, index + 1, reason: step.what);
      expect(step.rules, isNotEmpty);
    }
  });

  test('a save says which version it is', () {
    expect(versionOf(const {}), 1);
    expect(versionOf(const {'layout': {}}), 1);
    expect(
      versionOf(const {
        'layout': {'v': 2},
      }),
      2,
    );
    expect(
      versionOf(const {
        'v': 3,
        'layout': {'v': 2},
      }),
      3,
    );
    expect(versionOf(LauncherConfig().toJson()), saveVersion);
    expect(
      needsDevice(const {
        'layout': {'v': 2},
      }),
      isTrue,
    );
    expect(needsDevice(LauncherConfig().toJson()), isFalse);
  });

  test('what is up to date, or from later, is left as it is', () {
    final now = LauncherConfig().toJson();
    expect(migrate(now), same(now));
    final later = {'v': saveVersion + 1, 'new': true};
    expect(migrate(later), same(later));
    final layout = Layout.initial(['app:a']).toJson();
    expect(migrateLayout(layout), same(layout));
  });

  group('from 2 to 3', () {
    final save = migrate(
      _v2(),
      device: const Device(names: {'input:x/HW15': 'HDMI 1'}),
    );
    final layout = Layout.fromJson(save['layout']! as Json);

    test('ids say what the thing is', () {
      expect(save['v'], saveVersion);
      expect((save['layout']! as Json)['v'], saveVersion);
      final root = layout.home.root;
      expect(root.items.map((i) => i.id), [
        'pane-inputs',
        'media',
        // What the device knows an app widget by.
        'iwidget1',
        'games',
      ]);
      final inner = root.items.first.pane!;
      expect(inner.id, 'inputs');
      expect(inner.items.map((i) => i.id), [
        'hdmi-1',
        // An input the device said nothing of, by the end of its own id.
        'hw16',
        'tizentube-cobalt',
        'mine',
      ]);
      expect(inner.items.map((i) => (i.source ?? i.ref)).last, 'app:kept');
    });

    test('and what went by an id follows it', () {
      expect(layout.inbox, 'inputs');
      expect(layout.removed, {'app:gone'});
      expect(
        (layout.home.root.items.first.source ??
            layout.home.root.items.first.ref),
        'inputs',
      );
      expect(layout.home.root.items.first.w, 4);
      expect(
        (layout.home.root.items.last.source ?? layout.home.root.items.last.ref),
        'games',
      );
      expect(layout.panel('games')!.title, 'Games');
      expect(layout.panel('games')!.root.id, 'games/root');
      expect(save['iconOverrides'], {
        'app:a': '/a.png',
        'panel:games': '/games.png',
      });
      // Nothing more for the model to put right.
      expect(layout.normalised().toJson(), layout.toJson());
    });

    test('and a sidebar is left looking as it does', () {
      expect(layout.panel('left')!.root.prefabRules, isEmpty);
      expect(layout.panel('left')!.root.columns, 3);
    });

    test('and the save handed in is not touched', () {
      final before = _v2();
      migrate(before);
      expect(before, _v2());
    });
  });

  group('from 1', () {
    final save = migrate({
      'wallpaper': '/w.mp4',
      'hidden': ['app:b', 'app:nowhere'],
      'iconOverrides': {'panel:pabcdefg': '/f.png'},
      'layout': {
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'sections': [
              {
                'id': 'main',
                'title': 'Apps',
                'items': [
                  _item('iaaaaaaa', 'app:com.example.a'),
                  _item('ibbbbbbb', 'app:b'),
                  _item('iccccccc', 'pabcdefg', 'panel'),
                ],
              },
            ],
          },
          {
            'id': 'left',
            'sections': [
              {
                'id': 'rail',
                'items': [_item('idddddddd', 'app:com.example.d')],
              },
            ],
          },
          {
            'id': 'pabcdefg',
            'title': 'Games',
            'sections': [
              {
                'id': 'sgggggggg',
                'items': [_item('ieeeeeee', 'app:b')],
              },
            ],
          },
        ],
      },
    });
    final config = LauncherConfig.fromJson(save);
    final layout = config.layout;

    test('goes through every step to this version', () {
      expect(save['v'], saveVersion);
      expect(save.keys, isNot(contains('wallpaper')));
      expect(save.keys, isNot(contains('hidden')));
      expect(config.wallpapers, ['/w.mp4']);

      // Sections are panes; the one on the home screen is inside its own.
      final main = layout.home.root.items.single;
      expect(main.kind, ItemKind.pane);
      expect(main.id, 'pane-main');
      expect(main.pane!.title, 'Apps');
      expect(layout.inbox, 'main');
      // What was hidden is gone from everywhere and stays off.
      expect(main.pane!.items.map((i) => i.id), ['example-a', 'games']);
      expect(layout.removed, {'app:b', 'app:nowhere'});
      expect(layout.panel('games')!.items, isEmpty);
      expect(config.iconOverrides, {'panel:games': '/f.png'});
      // A sidebar from then looks as it did then.
      final left = layout.panel('left')!.root;
      expect(left.prefabRules[cardPrefabId], {layoutOption: 'row'});
      expect(left.rowHeight, 36);
      expect(
        (left.items.single.source ?? left.items.single.ref),
        'app:com.example.d',
      );
    });

    test('and once there, stays as it is', () {
      final written = config.toJson();
      expect(migrate(written), same(written));
      expect(LauncherConfig.fromJson(written).toJson(), written);
    });
  });

  test('a layout on its own goes through the same steps', () {
    final layout = Layout.fromJson(const {
      'panels': [
        {
          'id': 'home',
          'sections': [
            {
              'id': 'sabcdefg',
              'items': [
                {'id': 'iabcdefg', 'ref': 'app:com.netflix.ninja'},
              ],
            },
          ],
        },
      ],
    });
    expect(layout.home.items.single.id, 'netflix-ninja');
    expect(layout.toJson()['v'], saveVersion);
    expect(
      () => Layout.fromJson(const {
        'panels': [
          {
            'id': 'home',
            'sections': [
              {'title': 'no id'},
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  group('from 3 to 4', () {
    Json v3([Object? menu]) => {
      'v': 3,
      'contextMenu': ?menu,
      'layout': {
        'v': 3,
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'pane': {'id': 'home/root', 'items': <Object?>[]},
          },
        ],
      },
    };
    List<Object?> menuOf(Json save) => [
      for (final panel in (save['layout']! as Json)['panels']! as List)
        if ((panel as Json)['id'] == 'quick-actions')
          for (final item in (panel['pane']! as Json)['items']! as List)
            ((item as Json)['options']! as Json)['label'],
    ];

    test('the chosen quick actions become buttons in a popup', () {
      final save = migrate(v3(['uninstall', 'hide', 'explode', 'open']));
      expect(save.containsKey('contextMenu'), isFalse);
      expect(menuOf(save), ['Uninstall', 'Remove', 'Open']);
      final menu = Layout.fromJson(save['layout']! as Json)
          .normalised()
          .panel(Layout.menuId)!;
      expect(menu.kind, PanelKind.popup);
      expect(menu.root.columns, 1);
      expect((menu.items.first.source ?? menu.items.first.ref), 'button');
      expect(menu.items.first.on.values.single.single.name, 'uninstall');
    });

    test('a save that chose none is left to the usual ones', () {
      final save = migrate(v3());
      expect(menuOf(save), isEmpty);
      final layout = Layout.fromJson(save['layout']! as Json).normalised();
      expect(layout.panel(Layout.menuId), isNull);
      // Read for showing, they are there.
      expect(
        layout.withEntities(const []).panel(Layout.menuId)!.items,
        hasLength(5),
      );
      // Emptied by the user, the menu stays empty.
      expect(menuOf(migrate(v3(<Object?>[]))), isEmpty);
      expect(
        Layout.fromJson(migrate(v3(<Object?>[]))['layout']! as Json)
            .withEntities(const [])
            .panel(Layout.menuId)!
            .items,
        isEmpty,
      );
    });
  });

  group('from 4 to 5', () {
    final layout = Layout.fromJson(const {
      'v': 4,
      'inbox': 'main',
      'panels': [
        {
          'id': 'home',
          'pane': {
            'id': 'main',
            'itemLook': 'row',
            'itemNames': true,
            'items': [
              {'id': 'a', 'ref': 'app:a', 'hideName': true, 'look': 'row'},
              {'id': 'b', 'ref': 'app:b'},
              {
                'id': 'c',
                'ref': 'app:c',
                'hideName': true,
                'options': {
                  'parts': {
                    'name': {'size': 20},
                  },
                },
              },
            ],
          },
        },
      ],
    });
    final [a, b, c] = layout.home.items.toList();

    test("a card's own look is what it sets differently from its prefab", () {
      expect(a.options, {
        'layout': 'row',
        'parts': {
          'name': {'hidden': true},
        },
      });
      expect(b.options, isEmpty);
      // What it already set for the part is kept beside it.
      expect(overridesOf(c, 'name'), {
        'style': {'fontSize': 20},
        'hidden': true,
      });
      expect(a.toJson().keys, isNot(contains('hideName')));
    });

    test('what a pane made of its cards is a rule for each prefab', () {
      final root = layout.home.root;
      for (final prefab in [cardPrefabId, folderPrefabId]) {
        expect(root.prefabRules[prefab], {
          'layout': 'row',
          'parts': {
            'name': {'hidden': false},
          },
        });
      }
      // The rule counts over the card: its name shows for as long.
      final shown = instanceOf(builtInPrefabs.first, root.shown.first)!;
      expect(shown.parts.last.hidden, isFalse);
      expect(instanceOf(builtInPrefabs.first, a)!.parts.last.hidden, isTrue);
      expect(Pane.fromJson(root.toJson()).prefabRules, root.prefabRules);
    });
  });

  group('from 5 to 6', () {
    final save = migrate({
      'v': 5,
      'prefabs': [
        {
          'id': 'big',
          'on': {
            'press': [
              {'do': 'info', 'card': 'app:x'},
            ],
          },
        },
      ],
      'layout': {
        'v': 5,
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'pane': {
              'id': 'main',
              'items': [
                {'id': 'a', 'kind': 'card', 'ref': 'app:a'},
                {
                  'id': 'b',
                  'kind': 'card',
                  'ref': 'app:b',
                  'options': {'prefab': 'big', 'layout': 'row'},
                  'on': {
                    'hold': [
                      {'do': 'open', 'card': 'app:a'},
                    ],
                  },
                },
                {
                  'id': 'c',
                  'kind': 'card',
                  'ref': 'app:c',
                  'options': {'prefab': 'big'},
                },
                {'id': 'clock', 'kind': 'widget', 'ref': 'clock'},
              ],
            },
          },
        ],
      },
    });
    final [a, b, c, clock] = Layout.fromJson(save['layout']! as Json).home.items
        .toList();

    test('a card is an instance of a prefab drawn from an entity', () {
      expect(
        (a.kind, a.ref, a.source),
        (ItemKind.prefab, cardPrefabId, 'app:a'),
      );
      expect((b.ref, b.source), ('big', 'app:b'));
      expect(b.options, {'layout': 'row'});
      expect((c.ref, c.source), ('big', 'app:c'));
      expect(c.options, isEmpty);
      expect(a.toJson(), {
        'id': 'a',
        'kind': 'prefab',
        'ref': 'app-card',
        'w': 1,
        'h': 1,
        'vars': {'source': 'app:a'},
      });
      // What was a widget of its own is an instance too, by a later step.
      expect(
        (clock.kind, clock.ref, clock.source),
        (ItemKind.prefab, 'clock', 'clock'),
      );
    });

    test('an action is done to an entity', () {
      expect(b.on.values.single.single.toJson(), {
        'do': 'open',
        'entity': 'app:a',
      });
      final prefab = LauncherConfig.fromJson(save).prefabs.single;
      expect(prefab.on.values.single.single.arg('entity'), 'app:x');
    });
  });

  group('from 6 to 7', () {
    Json item(String id, Json more) => {
      'id': id,
      'kind': 'widget',
      'ref': 'text',
      ...more,
    };
    final save = migrate({
      'v': 6,
      'prefabs': [
        {
          'id': 'big',
          'parts': {
            'a': {'kind': 'text', 'text': '{{nowPlaying.title}} at {{time}}'},
          },
        },
      ],
      'layout': {
        'v': 6,
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'pane': {
              'id': 'main',
              'items': [
                item('a', {
                  'options': {
                    'text':
                        '{{time}} {{ time.hour }}:{{time.minute}} '
                        '{{date}} {{date.weekday}} {{time | format:h:mm a}} '
                        '{{nowPlaying}} {{nowPlaying.title | default:None}} '
                        '{{timetable.next}} {{weather}} time',
                    'size': 20,
                  },
                }),
                item('b', {
                  'on': {
                    'press': [
                      {'do': 'media', 'command': 'next'},
                      {'do': 'media'},
                      {'do': 'open'},
                    ],
                  },
                }),
              ],
            },
          },
        ],
      },
    });
    final [a, b] = Layout.fromJson(save['layout']! as Json).home.items.toList();

    test('what was a value of the launcher is read off an entity', () {
      expect(
        a.options['text'],
        '{{clock.time}} {{clock.hour}}:{{clock.minute}} '
        '{{clock.date}} {{clock.weekday}} {{clock | format:h:mm a}} '
        '{{media}} {{media.title | default:None}} '
        // Not one of them, for all it starts like one; nor is plain text.
        '{{timetable.next}} {{weather}} time',
      );
      expect(a.style['fontSize'], 20);
      final prefab = LauncherConfig.fromJson(save).prefabs.single;
      expect(
        prefab.parts['a']!.options['text'],
        '{{media.title}} at {{clock.time}}',
      );
    });

    test('the media player is told what to do as its own actions', () {
      expect(
        [for (final act in b.on.values.single) act.toJson()],
        [
          {'do': 'next', 'entity': 'media'},
          {'do': 'playPause', 'entity': 'media'},
          {'do': 'open'},
        ],
      );
    });
  });

  group('from 7 to 8', () {
    Json widget(String ref, [Json? options]) => {
      'id': ref,
      'kind': 'widget',
      'ref': ref,
      'w': 3,
      'h': 2,
      'options': ?options,
    };
    final save = migrate({
      'v': 7,
      'layout': {
        'v': 7,
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'pane': {
              'id': 'main',
              'items': [
                widget('clock', {
                  'hour24': false,
                  'seconds': true,
                  'date': false,
                }),
                {...widget('clock'), 'id': 'plain'},
                widget('weather', {
                  'place': 'Perth',
                  'latitude': -31.95,
                  'longitude': 115.86,
                  'fahrenheit': true,
                }),
                widget('media'),
                widget('text', {'text': 'Hi'}),
              ],
            },
          },
        ],
      },
    });
    final [clock, plain, weather, media, text] = Layout.fromJson(
      save['layout']! as Json,
    ).home.items.toList();

    test('each is an instance of a prefab drawn from its entity', () {
      expect(
        (clock.kind, clock.ref, clock.source),
        (ItemKind.prefab, 'clock', 'clock'),
      );
      expect((weather.ref, weather.source), ('weather', 'weather'));
      expect((media.ref, media.source), ('now-playing', 'media'));
      // As big as it was.
      expect((clock.w, clock.h), (3, 2));
      // Any other widget is what it was.
      expect((text.kind, text.ref), (ItemKind.component, 'text'));
      expect(text.options, {'text': 'Hi'});
      // And there is a prefab for each to be an instance of.
      for (final item in [clock, weather, media]) {
        final prefab = builtInPrefabs.firstWhere((p) => p.id == item.ref);
        expect(instanceOf(prefab, item), isNotNull);
      }
    });

    test('what a widget was set to is what its instance sets', () {
      expect(overridesOf(clock, 'time'), {
        'text': '{{source | format:h:mm:ss a}}',
      });
      expect(overridesOf(clock, 'date'), {'hidden': true});
      expect(plain.options, isEmpty);
      expect(overridesOf(weather, 'temperature'), {
        'text': '{{source.temperature | times:1.8 | plus:32 | round}}°',
      });
      // The place the weather widget had is the launcher's now.
      expect(LauncherConfig.fromJson(save).place?.name, 'Perth');
    });
  });

  group('from 8 to 9', () {
    test('what an instance is drawn from is one of its variables', () {
      final save = migrate({
        'v': 8,
        'layout': {
          'v': 8,
          'inbox': 'main',
          'panels': [
            {
              'id': 'home',
              'pane': {
                'id': 'main',
                'items': [
                  {
                    'id': 'a',
                    'kind': 'prefab',
                    'ref': 'app-card',
                    'source': 'app:a',
                    'vars': {'tint': 'red'},
                  },
                  {'id': 't', 'kind': 'widget', 'ref': 'text'},
                ],
              },
            },
          ],
        },
      });
      final [a, t] = Layout.fromJson(save['layout']! as Json).home.items
          .toList();
      expect(a.source, 'app:a');
      expect(a.toJson()['vars'], {'tint': 'red', 'source': 'app:a'});
      expect(a.toJson().containsKey('source'), isFalse);
      expect(t.vars, isEmpty);
    });
  });

  group('from 9 to 10', () {
    test('what opened a folder sets its `open`', () {
      final save = migrate({
        'v': 9,
        'layout': {
          'v': 9,
          'inbox': 'main',
          'panels': [
            {
              'id': 'home',
              'pane': {
                'id': 'main',
                'items': [
                  {
                    'id': 'b',
                    'kind': 'widget',
                    'ref': 'button',
                    'on': {
                      'press': [
                        {'do': 'panel', 'panel': 'games'},
                        {'do': 'settings'},
                      ],
                    },
                  },
                ],
              },
            },
          ],
        },
      });
      final item = Layout.fromJson(save['layout']! as Json).home.items.single;
      expect(
        [for (final act in item.on.values.single) act.toJson()],
        [
          {'do': 'set', 'var': 'open', 'value': true, 'of': 'games'},
          {'do': 'settings'},
        ],
      );
    });
  });

  group('from 10 to 11', () {
    test('what opens a folder is an instance drawn from it', () {
      final save = migrate({
        'v': 10,
        'layout': {
          'v': 10,
          'inbox': 'main',
          'panels': [
            {
              'id': 'home',
              'pane': {
                'id': 'main',
                'items': [
                  {'id': 'f', 'kind': 'panel', 'ref': 'games', 'w': 2},
                  {
                    'id': 'g',
                    'kind': 'panel',
                    'ref': 'games',
                    'options': {'prefab': 'my-folder', 'layout': 'row'},
                  },
                ],
              },
            },
            {
              'id': 'games',
              'title': 'Games',
              'pane': {'id': 'games/root', 'items': <Object?>[]},
            },
          ],
        },
      });
      final layout = Layout.fromJson(save['layout']! as Json).normalised();
      final [f, g] = layout.home.items.toList();
      expect(
        (f.kind, f.ref, f.source, f.w),
        (ItemKind.prefab, folderPrefabId, 'games', 2),
      );
      expect((g.ref, g.source), ('my-folder', 'games'));
      expect(g.options, {'layout': 'row'});
      expect(layout.folderOf(f), 'games');
      expect(f.toJson().keys, isNot(contains('options')));
    });
  });

  test('from 12 to 13, what said it was a widget says component', () {
    final save = migrate({
      'v': 12,
      'layout': {
        'v': 12,
        'panels': [
          {
            'id': 'home',
            'pane': {
              'id': 'home/root',
              'items': [
                {'id': 't', 'kind': 'widget', 'ref': 'text'},
                {
                  'id': 'p',
                  'kind': 'prefab',
                  'ref': 'app-card',
                  'vars': {'source': 'app:a'},
                },
              ],
            },
          },
        ],
      },
    });
    final home = LauncherConfig.fromJson(save).layout.home;
    expect(
      [for (final item in home.items) item.kind],
      [ItemKind.component, ItemKind.prefab],
    );
    expect(
      home.root.toJson()['items'],
      contains(containsPair('kind', 'component')),
    );
  });

  test('from 13 to 14, settings are gathered as rules', () {
    final save = migrate({
      'v': 13,
      'layout': {
        'v': 13,
        'panels': [
          {
            'id': 'left',
            'closed': 64,
            'width': 'fill',
            'opening': 'slide',
            'reveal': 'always',
            'pane': {
              'id': 'left/root',
              'columns': 1,
              'rowHeight': 36,
              'itemW': 1,
              'rules': {
                'app-card': {'layout': 'row'},
              },
              'items': <Object?>[],
            },
          },
        ],
      },
    });
    final left = LauncherConfig.fromJson(save).layout.panel('left')!;
    // What was only the usual is not kept.
    expect(left.rules, {'closed': 64, 'width': 'fill', 'opening': 'slide'});
    expect((left.width, left.closed), (Panel.fill, 64));
    expect(left.root.rules, {'rowHeight': 36, 'itemW': 1});
    expect(left.root.prefabRules, {
      'app-card': {'layout': 'row'},
    });
  });

  group('from 11 to 12', () {
    final save = migrate({
      'v': 11,
      'prefabs': [
        {
          'id': 'mine',
          'parts': {
            'mark': {
              'kind': 'icon',
              'icon': 'sun',
              'size': 30,
              'colour': '#ff0000',
            },
            'says': {'kind': 'text', 'text': 'Hi', 'size': 18, 'bold': true},
            'cover': {'kind': 'picture', 'source': 'x', 'round': 12},
          },
          'layouts': {
            'row': {
              'direction': 'row',
              'parts': [
                {'part': 'mark'},
                {
                  'group': {
                    'parts': [
                      {
                        'part': 'says',
                        'options': {'align': 'left'},
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      ],
      'layout': {
        'v': 11,
        'inbox': 'main',
        'panels': [
          {
            'id': 'home',
            'pane': {
              'id': 'main',
              'padding': 24,
              'corners': [8, 8, 8, 8],
              'style': {
                'colors': ['#000000', '#ffffff'],
                'stops': [0, 0.8],
                'angle': 90,
                'border': '#ffffff55',
              },
              'rules': {
                'app-card': {
                  'layout': 'row',
                  'parts': {
                    'name': {'hidden': true, 'weight': 'bold'},
                  },
                },
              },
              'items': [
                {
                  'id': 't',
                  'kind': 'widget',
                  'ref': 'text',
                  'style': {
                    'colors': ['#112233'],
                  },
                  'options': {
                    'text': 'Hello',
                    'size': 20,
                    'weight': 'medium',
                    'align': 'right',
                    'colour': '#00ff00',
                  },
                },
                {
                  'id': 'i',
                  'kind': 'widget',
                  'ref': 'icon',
                  'options': {'icon': 'sun', 'size': 40, 'colour': '#ffff00'},
                },
                {
                  'id': 'p',
                  'kind': 'widget',
                  'ref': 'picture',
                  'options': {'round': 20},
                },
                {
                  'id': 'w',
                  'kind': 'prefab',
                  'ref': 'weather',
                  'vars': {'source': 'weather'},
                  'options': {
                    'parts': {
                      'icon': {'size': 60, 'colour': '#ffffff'},
                      'place': {'size': 10, 'hidden': true},
                    },
                  },
                },
                {
                  'id': 'c',
                  'kind': 'pane',
                  'pane': {
                    'id': 'inner',
                    'corners': [0, 4, 8, 12],
                    'items': <Object?>[],
                  },
                },
              ],
            },
          },
        ],
      },
    });
    final config = LauncherConfig.fromJson(save);
    final root = config.layout.home.root;
    final [t, i, p, w, c] = root.items;

    test("a box's colours, corners and padding are its look", () {
      expect(root.style, {
        'background': {
          'colors': ['#000000', '#ffffff'],
          'stops': [0, 0.8],
          'angle': 90,
        },
        'borderColor': '#ffffff55',
        'radius': 8,
        'padding': 24,
      });
      expect(root.toJson().keys, isNot(contains('padding')));
      expect(root.toJson().keys, isNot(contains('corners')));
      expect(c.pane!.style, {
        'radius': [0, 4, 8, 12],
      });
    });

    test("a widget's own look joins that of its box", () {
      expect(t.style, {
        'background': '#112233',
        'color': '#00ff00',
        'textAlign': 'right',
        'fontWeight': 'medium',
        'fontSize': 20,
      });
      expect(t.options, {'text': 'Hello'});
      // The size of a small picture is not one of letters.
      expect(i.options, {'icon': 'sun', 'size': 40});
      expect(i.style, {'color': '#ffff00'});
      expect(p.style, {'radius': 20});
      expect(p.options, isEmpty);
    });

    test('so does what is set for a part of a prefab', () {
      expect(overridesOf(w, 'icon'), {
        'size': 60,
        'style': {'color': '#ffffff'},
      });
      expect(overridesOf(w, 'place'), {
        'hidden': true,
        'style': {'fontSize': 10},
      });
      expect(root.prefabRules['app-card'], {
        'layout': 'row',
        'parts': {
          'name': {
            'hidden': true,
            'style': {'fontWeight': 'bold'},
          },
        },
      });
    });

    test("and what the user's own prefabs say of theirs", () {
      final prefab = config.prefabs.single;
      expect(prefab.parts['mark']!.options, {
        'icon': 'sun',
        'size': 30,
        'style': {'color': '#ff0000'},
      });
      expect(prefab.parts['says']!.options, {
        'text': 'Hi',
        'style': {'fontWeight': 'bold', 'fontSize': 18},
      });
      expect(prefab.parts['cover']!.options['style'], {'radius': 12});
      final [mark, says] = instanceOf(
        prefab,
        const LayoutItem(id: 'x', kind: ItemKind.prefab, ref: 'mine'),
      )!.parts;
      expect(mark.options['size'], 30);
      // What the layout says of a part is set over the part's own look.
      expect(says.options['style'], {
        'fontWeight': 'bold',
        'fontSize': 18,
        'textAlign': 'left',
      });
    });
  });
}
