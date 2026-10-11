import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';

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
      expect(inner.items.map((i) => i.ref).last, 'app:kept');
    });

    test('and what went by an id follows it', () {
      expect(layout.inbox, 'inputs');
      expect(layout.removed, {'app:gone'});
      expect(layout.home.root.items.first.ref, 'inputs');
      expect(layout.home.root.items.first.w, 4);
      expect(layout.home.root.items.last.ref, 'games');
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
      expect(layout.panel('left')!.root.itemLook, isNull);
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
      expect(left.itemLook, TileLook.row);
      expect(left.rowHeight, 36);
      expect(left.items.single.ref, 'app:com.example.d');
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
      expect(menu.items.first.ref, 'button');
      expect(menu.items.first.on.values.single.single.name, 'uninstall');
    });

    test('a save that chose none is left to the usual ones', () {
      final save = migrate(v3());
      expect(menuOf(save), isEmpty);
      final layout = Layout.fromJson(save['layout']! as Json).normalised();
      expect(layout.panel(Layout.menuId), isNull);
      // Read for showing, they are there.
      expect(
        layout.withCards(const []).panel(Layout.menuId)!.items,
        hasLength(5),
      );
      // Emptied by the user, the menu stays empty.
      expect(menuOf(migrate(v3(<Object?>[]))), isEmpty);
      expect(
        Layout.fromJson(migrate(v3(<Object?>[]))['layout']! as Json)
            .withCards(const [])
            .panel(Layout.menuId)!
            .items,
        isEmpty,
      );
    });
  });
}
