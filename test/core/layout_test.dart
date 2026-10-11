import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// An instance of the prefab a card is, handed what [ref] names; or with
/// a [kind], a primitive of that kind.
Component _item(
  String id, {
  String? kind,
  String? ref,
  double w = 1,
  double h = 1,
  double? x,
  double? y,
}) => kind == null
    ? Component.of(ref ?? id, id: id, w: w, h: h, x: x, y: y)
    : Component(id: id, kind: kind, w: w, h: h, x: x, y: y);

Entity _entity(String name) =>
    Entity(id: 'app:$name', kind: appKind, label: name);

Panel _home(Component root) => Panel(id: 'home', root: root);

void main() {
  group('placeItems', () {
    test('flow fills rows in order and wraps', () {
      final placed = placeItems(
        [_item('a'), _item('b', w: 2), _item('c'), _item('d')],
        3,
        PaneMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 1),
        Placement(1, 0, 2, 1),
        Placement(0, 1, 1, 1),
        Placement(1, 1, 1, 1),
      ]);
      expect(rowCount(placed), 2);
    });

    test('flow goes around a tall item and never goes back', () {
      final placed = placeItems(
        [_item('tall', h: 2), _item('wide', w: 2), _item('c'), _item('d')],
        3,
        PaneMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 2),
        Placement(1, 0, 2, 1),
        Placement(1, 1, 1, 1),
        Placement(2, 1, 1, 1),
      ]);
    });

    test('an item wider than the section is cut down to fit', () {
      expect(placeItems([_item('a', w: 4)], 2, PaneMode.flow), const [
        Placement(0, 0, 2, 1),
      ]);
    });

    test('grid keeps positions and leaves gaps', () {
      final placed = placeItems(
        [_item('a', x: 2, y: 1), _item('b', x: 0, y: 0)],
        4,
        PaneMode.grid,
      );
      expect(placed, const [Placement(2, 1, 1, 1), Placement(0, 0, 1, 1)]);
    });

    test('grid moves aside what has no position or collides', () {
      final placed = placeItems(
        [
          _item('first', x: 0, y: 0, w: 2),
          _item('clash', x: 1, y: 0),
          _item('new'),
          _item('off', x: 3, y: 0, w: 2),
        ],
        4,
        PaneMode.grid,
      );
      expect(placed, const [
        Placement(0, 0, 2, 1),
        Placement(2, 0, 1, 1),
        Placement(3, 0, 1, 1),
        Placement(0, 1, 2, 1),
      ]);
    });
  });

  group('free placement', () {
    test('items are where they say, fractions and overlaps included', () {
      final placed = placeItems(
        [
          _item('a', x: 0.5, y: 0.25, w: 1.5, h: 0.75),
          _item('b', x: 1, y: 0.5),
          _item('c'),
        ],
        4,
        PaneMode.free,
      );
      // What has no position lines up below what has, not on top of it.
      expect(placed, const [
        Placement(0.5, 0.25, 1.5, 0.75),
        Placement(1, 0.5, 1, 1),
        Placement(0, 2, 1, 1),
      ]);
      expect(rowCount(placed), 3);
    });

    test('several without a position fill rows under the rest', () {
      final placed = placeItems(
        [
          _item('placed', x: 0, y: 0, h: 1.2),
          _item('a', w: 2),
          _item('b', w: 2, h: 2),
          _item('c'),
        ],
        4,
        PaneMode.free,
      );
      expect(placed.skip(1), const [
        Placement(0, 2, 2, 1),
        Placement(2, 2, 2, 2),
        Placement(0, 4, 1, 1),
      ]);
    });
  });

  group('panes', () {
    Component pane(
      String id, {
      PaneMode mode = PaneMode.flow,
      List<Component>? children,
    }) => Component.pane(
      id: id,
      mode: mode,
      columns: 4,
      children: children ?? const [],
    );

    test('nest, and are found with what is in them', () {
      final root = pane(
        'global',
        mode: PaneMode.free,
        children: [
          _item('loose', ref: 'app:a'),
          pane(
            'outer',
            children: [
              _item('in-outer', ref: 'app:b'),
              pane('inner', children: [_item('in-inner', ref: 'app:c')]),
            ],
          ).sized(3, 2.5, x: 0.5, y: 1),
        ],
      );
      expect(root.panes.map((p) => p.id), ['global', 'outer', 'inner']);
      // An entity can sit in the global pane, outside every other.
      expect(root.contents.map((i) => i.handed.firstOrNull), [
        'app:a',
        'app:b',
        'app:c',
      ]);

      final layout = Layout(inbox: 'inner', panels: [_home(root)]).normalised();
      expect(layout.inbox, 'inner');
      final outer = layout.home.root.children.last;
      expect((outer.x, outer.y, outer.w, outer.h), (0.5, 1, 3, 2.5));
      final json = layout.toJson();
      expect(Layout.fromJson(json).normalised().toJson(), json);

      // New entities turn up in the inbox, however deep it is.
      final shown = layout.withEntities(['app:a', 'app:b', 'app:c', 'app:new']);
      final inner = shown.home.root.panes.last;
      expect(inner.children.map((i) => i.handed.firstOrNull), [
        'app:c',
        'app:new',
      ]);
      // Removing an entity takes it out of every pane.
      expect(
        shown
            .without({'app:b', 'app:c'})
            .home
            .items
            .map((i) => i.handed.firstOrNull),
        ['app:a', 'app:new'],
      );
    });

    test('normalised repairs what is wrong and keeps what is right', () {
      Component nest(int depth) => pane(
        'p$depth',
        children: [
          _item('entity$depth', ref: 'app:$depth'),
          if (depth < 6) nest(depth + 1),
        ],
      );
      final layout = Layout(
        inbox: 'nowhere',
        panels: [
          Panel(
            id: 'left',
            root: Component.pane(
              id: 'rail',
              columns: 4,
              children: [
                _item('a', w: 3),
                pane('in-rail', children: [_item('b')]),
              ],
            ),
          ),
          Panel(
            id: 'games',
            title: 'Games',
            root: pane(
              'rail',
              mode: PaneMode.grid,
              children: [
                _item('a', x: 9, y: 2, w: 2, h: 99),
                _item('half', x: 1),
                Component.of('missing', id: 'gone', prefab: folderPrefabId),
                Component.of('games', id: 'open', prefab: folderPrefabId),
                const Component(id: 'empty'),
                nest(2),
              ],
            ),
          ),
          Panel.empty('games', title: 'Duplicate'),
        ],
      ).normalised();

      expect(layout.panels.map((p) => p.id), ['home', 'left', 'games']);
      // Home was missing: it gets a global pane, which becomes the inbox.
      expect(layout.inbox, layout.home.root.id);
      expect(layout.home.root.mode, PaneMode.grid);

      // A sidebar is a pane like any other: it keeps its columns, its
      // widths and the pane inside it.
      final rail = layout.panel('left')!.root;
      expect(rail.columns, 4);
      expect(rail.children.map((i) => (i.id, i.isPane, i.w)), [
        ('a', false, 3),
        ('in-rail', true, 1),
      ]);
      expect(rail.children.last.children.single.id, 'b');

      final games = layout.panel('games')!;
      expect(games.title, 'Games');
      expect(games.root.id, isNot(rail.id));
      final [a, half, open, nested] = games.root.children;
      expect(a.id, isNot('a'));
      expect((a.x, a.y, a.w, a.h), (2, 2, 2, Component.maxRows));
      expect((half.x, half.y), (null, null));
      expect(open.handed.firstOrNull, 'games');
      // Panes deeper than allowed give their contents to the last that is.
      final depths = games.root.panes.map((p) => p.id).toList();
      expect(depths, hasLength(Component.maxDepth));
      expect(nested.contents.map((i) => i.handed.firstOrNull), [
        for (var depth = 2; depth <= 6; depth++) 'app:$depth',
      ]);
      final ids = [
        for (final panel in layout.panels)
          for (final p in panel.root.panes) ...p.children.map((i) => i.id),
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('fractions survive repair in a free pane and nowhere else', () {
      Component of(String id, PaneMode mode) => Component.pane(
        id: id,
        mode: mode,
        columns: 4,
        children: [_item('$id-a', x: 3.6, y: 0.3, w: 1.5, h: 0.1)],
      );
      final layout = Layout(
        inbox: 'f',
        panels: [
          _home(
            pane(
              'global',
              children: [of('f', PaneMode.free), of('g', PaneMode.grid)],
            ),
          ),
        ],
      ).normalised();
      final [free, grid] = layout.home.items.toList();
      // Kept inside the pane, and no smaller than a quarter cell.
      expect((free.x, free.y, free.w, free.h), (2.5, 0.3, 1.5, 0.25));
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
    });

    test('rejects what is not a layout', () {
      expect(
        () => Layout.fromJson(const {'panels': 'no'}),
        throwsFormatException,
      );
      expect(
        () => Layout.fromJson(const {
          'panels': [
            {
              'id': 'home',
              'root': {
                'id': 's',
                'kind': 'pane',
                'children': [
                  {'id': 1, 'kind': 'text'},
                ],
              },
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('a new layout', () {
    test('a new home screen is one pane as tall as the screen', () {
      final layout = Layout.initial(['app:b', 'app:gone'])
          .withEntities(['app:a', 'app:b']);
      final item = layout.home.root.children.single;
      expect(item.children.map((i) => i.handed.firstOrNull), [
        'app:b',
        'app:a',
      ]);
      expect(layout.inbox, item.id);
      // From under the top margin to the bottom one, on a 540-high screen.
      expect(item.h, closeTo(7.7, 0.1));
    });
  });

  test('a pane keeps the spacing it is given, within reason', () {
    Component pane(String id, double? spacing) => Component.pane(
      id: id,
      rules: {'spacing': ?spacing},
      children: [_item('$id-a')],
    );
    final layout = Layout(
      inbox: 'a',
      panels: [
        _home(
          Component.pane(
            id: 'global',
            rules: const {'spacing': 4},
            children: [pane('a', null), pane('b', 0), pane('c', 500)],
          ),
        ),
      ],
    ).normalised();
    final panes = layout.home.root.panes.toList();
    expect(panes.map((p) => p.spacing), [4, null, 0, Component.maxSpacing]);
    // Unset, it is the usual gap, wider across than down.
    expect((panes[1].spacingX, panes[1].spacingY), (20, 16));
    expect((panes[2].spacingX, panes[2].spacingY), (0, 0));
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
    expect(layout.withEntities(['app:x']).home.root.spacing, 4);
  });

  test('a pane keeps the padding it is given, within reason', () {
    final layout = Layout.fromJson(const {
      'v': saveVersion,
      'panels': [
        {
          'id': 'home',
          'root': {
            'id': 'global',
            'kind': 'pane',
            'style': {'padding': 24},
            'children': [
              {
                'id': 'a',
                'kind': 'pane',
                'style': {'padding': 900},
              },
              {'id': 'b', 'kind': 'pane'},
            ],
          },
        },
      ],
    }).normalised();
    expect(layout.home.root.panes.map((p) => p.box.padding), [24, 80, null]);
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
  });

  group('resolveLayout', () {
    final entities = [_entity('a'), _entity('b'), _entity('c')];

    test('matches items to entities, folders, widgets and panes', () {
      final config = LauncherConfig(
        iconOverrides: {'panel:games': '/games.png'},
        layout: Layout(
          inbox: 'main',
          removed: const {'app:c'},
          panels: [
            _home(
              Component.pane(
                id: 'global',
                children: [
                  Component.of('games', id: 'folder', prefab: folderPrefabId),
                  _item('clock', kind: 'clock'),
                  Component.pane(id: 'main'),
                ],
              ),
            ),
            Panel(
              id: 'games',
              title: 'Games',
              root: Component.pane(id: 'inside', children: [_item('app:b')]),
            ),
          ],
        ),
      );
      final view = resolveLayout(entities, config);
      final [folder, clock, pane] = view.home.root.children;

      // Handed a folder, not an entity.
      expect(config.layout.folderOf(folder), 'games');
      expect(clock.kind, 'clock');
      // The entity placed nowhere turns up in the inbox pane; the removed
      // one does not.
      expect(pane.children.single.handed.firstOrNull, 'app:a');
      expect(view.home.root.contents, hasLength(3));
      expect(view.bars, isEmpty);
    });

    test('the same entity can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'global',
          panels: [
            _home(
              Component.pane(
                id: 'global',
                children: [
                  _item('one', ref: 'app:a'),
                  _item('two', ref: 'app:a'),
                ],
              ),
            ),
          ],
        ).normalised(),
      );
      final entries = resolveLayout(entities, config).home.root.children;
      expect(entries.map((e) => e.handed.firstOrNull), [
        'app:a',
        'app:a',
        'app:b',
        'app:c',
      ]);
    });
  });

  group('sidebars and what panes decide', () {
    test('there is one for each edge, each with its usual size', () {
      final left = Panel.empty(Layout.leftId);
      final top = Panel.empty(Layout.topId);
      expect(left.kind, PanelKind.sidebar);
      expect(
        (left.edge, left.openWidth, left.openHeight, left.closedSize),
        (BarEdge.left, 260, Panel.fill, 96),
      );
      // Along a side it starts as a line of small rows.
      expect(left.root.rowHeight, Component.barRowHeight);
      expect(left.root.prefabRules[cardPrefabId], {'variant': 'row'});
      expect(
        (top.edge, top.openWidth, top.openHeight, top.closedSize),
        (BarEdge.top, Panel.fill, 120, 0),
      );
      expect(Panel.kindOf('bottom'), PanelKind.sidebar);
      expect(Panel.kindOf('elsewhere'), PanelKind.popup);
    });

    test('sizes are written, read back and kept within bounds', () {
      final layout = Layout(
        inbox: 'main',
        panels: [
          Panel.empty(Layout.homeId),
          Panel.empty(Layout.rightId)
              .withRule('width', Panel.fill)
              .withRule('height', 300)
              .withRule('closed', 0),
          Panel.empty(
            Layout.bottomId,
            rules: const {'height': 5000, 'closed': -3},
          ),
        ],
      ).normalised();
      final copy = Layout.fromJson(layout.toJson());
      final right = copy.panel(Layout.rightId)!;
      expect((right.width, right.height, right.closed), (Panel.fill, 300, 0));
      final bottom = copy.panel(Layout.bottomId)!;
      expect((bottom.height, bottom.closed), (Panel.maxExtent, 0));
      expect(bottom.width, isNull);
    });

    test('how one opens is written and read back, the usual left out', () {
      final usual = Panel.empty(Layout.leftId);
      expect(
        (usual.rule('opening'), usual.rule('reveal')),
        ('expand', 'always'),
      );
      expect(usual.toJson().keys, isNot(contains('rules')));

      final layout = Layout(
        inbox: 'main',
        panels: [
          Panel.empty(Layout.homeId),
          Panel.empty(
            Layout.leftId,
            rules: const {'opening': 'slide', 'reveal': 'late'},
          ),
        ],
      ).normalised();
      final left = Layout.fromJson(layout.toJson()).panel(Layout.leftId)!;
      expect((left.rule('opening'), left.rule('reveal')), ('slide', 'late'));

      // A word it does not know is taken as the usual.
      final odd = Layout(
        inbox: 'main',
        panels: [left.withRule('opening', 'spin')],
      ).normalised().panel(Layout.leftId)!;
      expect((odd.rule('opening'), odd.rule('reveal')), ('expand', 'late'));
    });

    test('a pane decides for its entities without changing what they say', () {
      const rules = {
        cardPrefabId: {
          'variant': 'row',
          'overrides': {
            'name': {'hidden': true},
          },
        },
      };
      final pane = Component.pane(
        id: 'p',
        rules: const {'itemW': 2},
        prefabRules: rules,
        children: [
          _item('a', w: 3, h: 2),
          _item('clock', kind: 'clock', w: 4),
          Component.pane(id: 'inner', w: 5),
        ],
      );
      final [entity, widget, inner] = pane.shown;
      expect((entity.w, entity.h), (2, 2));
      expect(entity.variant, 'row');
      expect(entity.overrides, {
        'name': {'hidden': true},
      });
      // Only entities and folders are decided for.
      expect((widget.w, inner.w), (4, 5));
      expect(widget.options, isEmpty);
      // What the entity says is still there for when the pane stops.
      expect(pane.children.first.w, 3);
      expect(pane.children.first.overrides, isEmpty);
      expect(Component.pane(id: 'p').decides, isFalse);
      // And all of it survives being written and read.
      final copy = Component.fromJson(
        pane.withOption('rowHeight', 40).toJson(),
      );
      expect(copy.prefabRules, rules);
      expect((copy.itemW, copy.rowHeight), (2, 40));
    });

    test('a pane keeps its look through being written and read', () {
      const style = {
        'background': '#101820cc',
        'radius': [0, 8, 20, 4],
        'color': '#ffd700',
      };
      final layout = Layout(
        inbox: 'p',
        panels: [
          Panel(
            id: Layout.homeId,
            root: Component.pane(id: 'p', style: style),
          ),
        ],
      ).normalised();
      expect(layout.home.root.style, style);
      final read = Component.fromJson(layout.home.root.toJson());
      expect(read.style, style);
      expect(read.box.corners, [0, 8, 20, 4]);
    });

    test('what is drawn is what the pane decides', () {
      final view = resolveLayout(
        const [Entity(id: 'app:a', kind: appKind, label: 'A')],
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              Panel(
                id: Layout.homeId,
                root: Component.pane(
                  id: 'main',
                  prefabRules: const {
                    cardPrefabId: {'variant': 'row'},
                  },
                  children: [_item('a', ref: 'app:a')],
                ),
              ),
            ],
          ),
        ),
      );
      expect(view.home.root.shown.single.variant, 'row');
    });
  });

  group('LauncherConfig', () {
    test('survives a JSON round trip', () {
      final config = LauncherConfig(
        layout: Layout.initial(['app:a']).without({'app:b'}),
        iconOverrides: {'app:a': '/x.png'},
        wallpapers: ['/w.mp4', '/x.png'],
        wallpaperEvery: 30,
        toasts: const ToastOptions(
          enabled: false,
          position: ToastPosition.bottomLeft,
          seconds: 9,
        ),
      );
      final copy = LauncherConfig.fromJson(config.toJson());
      expect(copy.toJson(), config.toJson());
      expect(copy.layout.removed, {'app:b'});
      expect(copy.copyWith(iconOverrides: {}).wallpaper, '/w.mp4');
      expect(copy.wallpaperEvery, 30);
      expect(copy.copyWith(wallpapers: const []).wallpaper, isNull);
    });

    test('a broken layout does not lose the rest', () {
      final config = LauncherConfig.fromJson(const {
        'layout': {'panels': 7},
        'wallpapers': ['/w.png'],
      });
      expect(config.wallpapers, ['/w.png']);
      expect(config.wallpaperEvery, 0);
      expect(config.layout.home.root.children, hasLength(1));
    });
  });
}
