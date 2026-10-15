import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
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

Entity _entity(String name) => Entity(
  id: 'system:app/$name',
  category: appCategory,
  label: name,
  placed: true,
);

Layer _home(Component root) => Layer(id: 'home', root: root);

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

    test('a pane that scrolls across keeps its children on one row', () {
      final items = [_item('a'), _item('b', w: 2), _item('c'), _item('d')];
      final wraps = Component.pane(id: 'p', columns: 3, children: items);
      expect(rowCount(placementsOf(wraps)), 2);
      expect(columnsOf(wraps), 3);

      final across = wraps.withOption('scrollX', true);
      expect(placementsOf(across), const [
        Placement(0, 0, 1, 1),
        Placement(1, 0, 2, 1),
        Placement(3, 0, 1, 1),
        Placement(4, 0, 1, 1),
      ]);
      // Its grid is as wide as they reach, and never narrower than its own.
      expect(columnsOf(across), 5);
      expect(columnsOf(across.copyWith(children: [_item('a')])), 3);
    });

    test('cells scroll down unless told not to, lines only when told to', () {
      Component pane(PaneMode mode, [Map<String, Object?> rules = const {}]) =>
          Component.pane(id: 'p', mode: mode, rules: rules);
      const both = {'scrollX': true, 'scrollY': true};
      for (final mode in [PaneMode.flow, PaneMode.grid, PaneMode.free]) {
        expect(
          (pane(mode).scrollsAcross, pane(mode).scrollsDown),
          (false, true),
        );
        final off = pane(mode, const {'scrollY': false});
        expect(off.scrollsDown, isFalse);
        expect(pane(mode, both).scrollsAcross, isTrue);
      }
      // A row scrolls along itself only, and so does a column.
      expect(pane(PaneMode.row).scrollsAcross, isFalse);
      expect(pane(PaneMode.column).scrollsDown, isFalse);
      expect(
        (
          pane(PaneMode.row, both).scrollsAcross,
          pane(PaneMode.row, both).scrollsDown,
        ),
        (true, false),
      );
      expect(
        (
          pane(PaneMode.column, both).scrollsAcross,
          pane(PaneMode.column, both).scrollsDown,
        ),
        (false, true),
      );
      // Scaled to its box, there is nothing to scroll.
      expect(
        pane(PaneMode.row, const {...both, 'fit': true}).scrollsAcross,
        isFalse,
      );
    });

    test('a scroll bar is for a pane that scrolls, and reads its look', () {
      final pane = Component.pane(id: 'p', rules: const {'scrollbar': 'thumb'});
      expect((pane.scrollbar, pane.scrollbarHides), ('thumb', false));
      expect(pane.withOption('scrollY', false).scrollbar, isNull);
      expect(pane.withOption('scrollbar', 'spinner').scrollbar, isNull);
      expect(pane.withOption('scrollbarShow', 'auto').scrollbarHides, isTrue);

      const plain = ScrollbarStyle();
      final unset = ScrollbarStyle.of(const {});
      expect(
        (unset.size, unset.margin, unset.length, unset.opacity, unset.start),
        (plain.size, plain.margin, plain.length, plain.opacity, plain.start),
      );
      expect(unset.thumb.colors, isEmpty);
      final look = ScrollbarStyle.of(const {
        'scrollbarSide': 'start',
        'scrollbarSize': 10,
        'scrollbarLength': 50,
        'scrollbarOpacity': 80,
        // More than leaves any thumb.
        'scrollbarInset': 20,
        'scrollbarThumb': {
          'colors': ['#ff0000', '#0000ff'],
          'angle': 90,
        },
        'scrollbarThumbRadius': 2,
        'scrollbarTrack': '#00000080',
        'scrollbarTrackBorder': '#ffffff',
        'scrollbarTrackBorderWidth': 'thick',
      });
      expect(
        (look.start, look.size, look.length, look.opacity),
        (true, 10, 0.5, 0.8),
      );
      expect(look.inset, 4.5);
      expect((look.thumb.colors.length, look.thumb.angle), (2, 90));
      expect(look.thumb.corners, [2, 2, 2, 2]);
      expect(look.track.colors, [0x80000000]);
      expect((look.track.border, look.track.borderWidth), (0xFFFFFFFF, 2));
      expect(look.track.corners, isNull);
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
          _item('loose', ref: 'system:app/a'),
          pane(
            'outer',
            children: [
              _item('in-outer', ref: 'system:app/b'),
              pane('inner', children: [_item('in-inner', ref: 'system:app/c')]),
            ],
          ).sized(3, 2.5, x: 0.5, y: 1),
        ],
      );
      expect(root.panes.map((p) => p.id), ['global', 'outer', 'inner']);
      // An entity can sit in the global pane, outside every other.
      expect(root.contents.map((i) => i.handed.firstOrNull), [
        'system:app/a',
        'system:app/b',
        'system:app/c',
      ]);

      final layout = Layout(inbox: 'inner', layers: [_home(root)]).normalised();
      expect(layout.inbox, 'inner');
      final outer = layout.home.root.children.last;
      expect((outer.x, outer.y, outer.w, outer.h), (0.5, 1, 3, 2.5));
      final json = layout.toJson();
      expect(Layout.fromJson(json).normalised().toJson(), json);

      // New entities turn up in the inbox, however deep it is.
      final shown = layout.withEntities([
        'system:app/a',
        'system:app/b',
        'system:app/c',
        'system:app/new',
      ]);
      final inner = shown.pane('inner')!;
      expect(inner.children.map((i) => i.handed.firstOrNull), [
        'system:app/c',
        'system:app/new',
      ]);
      // Removing an entity takes it out of every pane.
      expect(
        shown
            .without({'system:app/b', 'system:app/c'})
            .items
            .where((i) => i.isInstance)
            .map((i) => i.handed.firstOrNull),
        ['system:app/a', 'system:app/new'],
      );
    });

    test('normalised repairs what is wrong and keeps what is right', () {
      Component nest(int depth) => pane(
        'p$depth',
        children: [
          _item('entity$depth', ref: 'system:app/$depth'),
          if (depth < 6) nest(depth + 1),
        ],
      );
      final layout = Layout(
        inbox: 'nowhere',
        layers: [
          Layer(
            id: 'over',
            root: Component.pane(
              id: 'rail',
              columns: 4,
              children: [
                _item('a', w: 3),
                // Something with a folder's id gives way to the folder.
                _item('games', ref: 'system:app/x'),
                pane('in-rail', children: [_item('b')]),
                // A folder: docked, so off the cells of the pane it is in.
                folderPane('games', title: 'Games')
                    .withOption('mode', 'grid')
                    .copyWith(
                      children: [
                        _item('a', x: 9, y: 2, w: 2, h: 99),
                        _item('half', x: 1),
                        Component.of(
                          'missing',
                          id: 'gone',
                          prefab: folderPrefabId,
                        ),
                        Component.of(
                          'games',
                          id: 'open',
                          prefab: folderPrefabId,
                        ),
                        const Component(id: 'empty'),
                        nest(2),
                      ],
                    ),
              ],
            ),
          ),
          Layer.empty('over'),
        ],
      ).normalised();

      // Home was missing: it comes first, with a root pane that becomes the
      // inbox.
      expect(layout.layers.map((l) => l.id), ['home', 'over']);
      expect(layout.inbox, layout.home.root.id);
      expect(layout.home.root.mode, PaneMode.grid);

      final rail = layout.layer('over')!.root;
      expect(rail.columns, 4);
      final [first, other, inRail, games] = rail.children;
      expect((first.id, first.w), ('a', 3));
      expect(other.id, isNot('games'));
      expect(inRail.children.single.id, 'b');

      expect((games.id, games.title, games.isDocked), ('games', 'Games', true));
      final [a, half, open, nested] = games.children;
      expect(a.id, isNot('a'));
      expect((a.x, a.y, a.w, a.h), (2, 2, 2, Component.maxRows));
      expect((half.x, half.y), (null, null));
      expect(open.handed.firstOrNull, 'games');
      // Panes deeper than allowed give their contents to the last that is.
      // A docked pane starts the count again.
      expect(games.panes, hasLength(Component.maxDepth));
      expect(nested.contents.map((i) => i.handed.firstOrNull), [
        for (var depth = 2; depth <= 6; depth++) 'system:app/$depth',
      ]);
      final ids = layout.all.map((c) => c.id).toList();
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
        layers: [
          _home(
            pane(
              'global',
              children: [of('f', PaneMode.free), of('g', PaneMode.grid)],
            ),
          ),
        ],
      ).normalised();
      final [free, grid] = layout.home.root.contents.toList();
      // Kept inside the pane, and no smaller than a quarter cell.
      expect((free.x, free.y, free.w, free.h), (2.5, 0.3, 1.5, 0.25));
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
    });

    test('rejects what is not a layout', () {
      expect(
        () => Layout.fromJson(const {'layers': 'no'}),
        throwsFormatException,
      );
      expect(
        () => Layout.fromJson(const {
          'layers': [
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
      final layout = Layout.initial(['system:app/b', 'system:app/gone'])
          .withEntities(['system:app/a', 'system:app/b']);
      // The quick actions come after it.
      final [item, menu] = layout.home.root.children;
      expect(menu.id, Layout.menuId);
      expect(item.children.map((i) => i.handed.firstOrNull), [
        'system:app/b',
        'system:app/a',
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
      layers: [
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
    expect(layout.withEntities(['system:app/x']).home.root.spacing, 4);
  });

  test('a pane keeps the padding it is given, within reason', () {
    final layout = Layout.fromJson(const {
      'v': saveVersion,
      'layers': [
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
        iconOverrides: {'folder:games': '/games.png'},
        layout: Layout(
          inbox: 'main',
          removed: const {'system:app/c'},
          layers: [
            _home(
              Component.pane(
                id: 'global',
                children: [
                  Component.of('games', id: 'folder', prefab: folderPrefabId),
                  _item('system:clock', kind: 'system:clock'),
                  Component.pane(id: 'main'),
                  folderPane(
                    'games',
                    title: 'Games',
                  ).copyWith(children: [_item('system:app/b')]),
                ],
              ),
            ),
          ],
        ),
      );
      final view = resolveLayout(entities, config);
      final [folder, clock, pane, games, menu] = view.home.root.children;

      // Handed a folder, not an entity.
      expect(config.layout.folderOf(folder), 'games');
      expect(clock.kind, 'system:clock');
      // The entity placed nowhere turns up in the inbox pane; the removed
      // one does not.
      expect(pane.children.single.handed.firstOrNull, 'system:app/a');
      expect(games.children.single.handed.firstOrNull, 'system:app/b');
      // The folder and the quick actions are docked: on the layer, off its
      // cells.
      expect(view.docked.map((p) => p.id), ['games', Layout.menuId]);
      expect(menu.hovers, isTrue);
      expect(placeItems(view.home.root.children, 5, PaneMode.flow).skip(3), [
        const Placement(0, 0, 0, 0),
        const Placement(0, 0, 0, 0),
      ]);
    });

    test('the same entity can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'global',
          layers: [
            _home(
              Component.pane(
                id: 'global',
                children: [
                  _item('one', ref: 'system:app/a'),
                  _item('two', ref: 'system:app/a'),
                ],
              ),
            ),
          ],
        ).normalised(),
      );
      final entries = resolveLayout(
        entities,
        config,
      ).home.root.children.where((e) => e.isInstance);
      expect(entries.map((e) => e.handed.firstOrNull), [
        'system:app/a',
        'system:app/a',
        'system:app/b',
        'system:app/c',
      ]);
    });
  });

  group('sidebars and what panes decide', () {
    test('a sidebar is a pane docked to an edge, with its usual size', () {
      final left = sidebarPane('left', 'left');
      final top = sidebarPane('top', 'top');
      expect((left.isDocked, left.hovers), (true, false));
      expect(
        (left.edge, left.openWidth, left.openHeight, left.closed),
        (BarEdge.left, 260, Component.fill, 96),
      );
      // Along a side it starts as a line of small rows.
      expect(left.rowHeight, Component.barRowHeight);
      expect(left.prefabRules[cardPrefabId], {'variant': 'row'});
      expect(
        (top.edge, top.openWidth, top.openHeight, top.closed),
        (BarEdge.top, Component.fill, 120, 0),
      );
      // It opens while it has the focus, by what is written on it.
      expect(left.on.keys, Trigger.values.skip(2));
      // A folder is hidden while closed; in the middle it is as tall as what
      // is in it.
      final folder = folderPane('games');
      expect(
        (folder.hovers, folder.edge, folder.openWidth, folder.openHeight),
        (true, null, 595, null),
      );
      // A word that is no dock leaves a pane on its parent's cells.
      const odd = {'dock': 'sky'};
      expect(Component.pane(id: 'p', rules: odd).isDocked, isFalse);
    });

    Layout holding(List<Component> docked) => Layout(
      inbox: 'main',
      layers: [_home(Component.pane(id: 'root', children: docked))],
    ).normalised();

    test('sizes are written, read back and kept within bounds', () {
      final layout = holding([
        sidebarPane('right', 'right')
            .withOption('width', 'fill')
            .withOption('height', 300)
            .withOption('closed', 0),
        sidebarPane(
          'bottom',
          'bottom',
        ).withOption('height', 5000).withOption('closed', -3),
        // One off an edge has no strip to show.
        folderPane('games').withOption('closed', 40),
      ]);
      final copy = Layout.fromJson(layout.toJson());
      final right = copy.pane('right')!;
      expect(
        (right.dockWidth, right.dockHeight, right.closed),
        (Component.fill, 300, 0),
      );
      final bottom = copy.pane('bottom')!;
      expect((bottom.dockHeight, bottom.closed), (Component.maxExtent, 0));
      expect(bottom.dockWidth, isNull);
      expect(copy.pane('games')!.hovers, isTrue);
    });

    test('how one opens is written and read back, the usual left out', () {
      final usual = sidebarPane('left', 'left');
      expect(
        (dockRule(usual, 'opening'), dockRule(usual, 'reveal')),
        ('expand', 'always'),
      );
      expect(usual.options.keys, isNot(contains('opening')));

      final layout = holding([
        usual.withOption('opening', 'slide').withOption('reveal', 'late'),
      ]);
      final left = Layout.fromJson(layout.toJson()).pane('left')!;
      expect(
        (dockRule(left, 'opening'), dockRule(left, 'reveal')),
        ('slide', 'late'),
      );

      // A word it does not know is taken as the usual.
      final odd = holding([left.withOption('opening', 'spin')]).pane('left')!;
      expect(
        (dockRule(odd, 'opening'), dockRule(odd, 'reveal')),
        ('expand', 'late'),
      );
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
          _item('system:clock', kind: 'system:clock', w: 4),
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
        layers: [_home(Component.pane(id: 'p', style: style))],
      ).normalised();
      expect(layout.home.root.style, style);
      final read = Component.fromJson(layout.home.root.toJson());
      expect(read.style, style);
      expect(read.box.corners, [0, 8, 20, 4]);
    });

    test('what is drawn is what the pane decides', () {
      final view = resolveLayout(
        const [Entity(id: 'system:app/a', category: appCategory, label: 'A')],
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              _home(
                Component.pane(
                  id: 'main',
                  prefabRules: const {
                    cardPrefabId: {'variant': 'row'},
                  },
                  children: [_item('a', ref: 'system:app/a')],
                ),
              ),
            ],
          ),
        ),
      );
      expect(view.home.root.shown.first.variant, 'row');
    });
  });

  group('LauncherConfig', () {
    test('survives a JSON round trip', () {
      final config = LauncherConfig(
        layout: Layout.initial(['system:app/a']).without({'system:app/b'}),
        iconOverrides: {'system:app/a': '/x.png'},
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
      expect(copy.layout.removed, {'system:app/b'});
      expect(copy.copyWith(iconOverrides: {}).wallpaper, '/w.mp4');
      expect(copy.wallpaperEvery, 30);
      expect(copy.copyWith(wallpapers: const []).wallpaper, isNull);
    });

    test('a broken layout does not lose the rest', () {
      final config = LauncherConfig.fromJson(const {
        'layout': {'layers': 7},
        'wallpapers': ['/w.png'],
      });
      expect(config.wallpapers, ['/w.png']);
      expect(config.wallpaperEvery, 0);
      expect(config.layout.home.root.children, hasLength(1));
    });
  });
}
