import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';

import '../support/packs.dart';

/// An instance of the prefab a card is, handed what [ref] names; or with
/// a [kind], a primitive of that kind.
Node _item(
  String id, {
  String? kind,
  String? ref,
  double w = 1,
  double h = 1,
  double? x,
  double? y,
}) => kind == null
    ? cardOf(ref ?? id, id: id, w: w, h: h, x: x, y: y)
    : drawn(id, kind, w: w, h: h, x: x, y: y);

Entity _entity(String name) => Entity(
  id: 'system:app/$name',
  category: appCategory,
  label: name,
  prefab: cardPrefabId,
  placed: true,
);

Layer _home(Node root) => Layer(id: 'home', root: root);

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
    test('without a layout there are no cells', () {
      expect(
        placeItems([_item('a', x: 1, y: 1), _item('b')], 4, PaneMode.free),
        const [Placement(0, 0, 0, 0), Placement(0, 0, 0, 0)],
      );
    });

    test('a pane that scrolls across keeps its children on one row', () {
      final items = [_item('a'), _item('b', w: 2), _item('c'), _item('d')];
      final wraps = Node.pane(id: 'p', columns: 3, children: items);
      expect(rowCount(placementsOf(wraps)), 2);
      expect(columnsOf(wraps), 3);

      final across = wraps.withValue(scrollModule.name, 'across', true);
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

    test('it scrolls the ways its Scroll module asks and its layout lets '
        'it', () {
      Node pane(
        PaneMode mode, [
        Map<String, Object?>? scroll,
        Map<String, Object?> layout = const {},
      ]) => Node.pane(id: 'p', mode: mode, scroll: scroll, layout: layout);
      const both = {'across': true, 'down': true};
      for (final mode in [PaneMode.flow, PaneMode.grid]) {
        // A new pane on cells scrolls down.
        expect(
          (pane(mode).scrollsAcross, pane(mode).scrollsDown),
          (false, true),
        );
        expect(pane(mode, const {}).scrollsDown, isFalse);
        expect(pane(mode, both).scrollsAcross, isTrue);
      }
      // Without a layout nothing scrolls.
      expect(
        (
          pane(PaneMode.free, both).scrollsAcross,
          pane(PaneMode.free, both).scrollsDown,
        ),
        (false, false),
      );
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
        pane(PaneMode.row, both, const {'fit': true}).scrollsAcross,
        isFalse,
      );
    });

    test('a scroll bar is for a pane that scrolls, and reads its look', () {
      final pane = Node.pane(
        id: 'p',
        scroll: const {'down': true, 'bar': 'thumb'},
      );
      Node set(String key, Object value) =>
          pane.withValue(scrollModule.name, key, value);
      expect((pane.scrollbar, pane.scrollbarHides), ('thumb', false));
      expect(set('down', false).scrollbar, isNull);
      expect(set('bar', 'spinner').scrollbar, isNull);
      expect(set('show', 'auto').scrollbarHides, isTrue);

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
  });

  group('panes', () {
    Node pane(
      String id, {
      PaneMode mode = PaneMode.flow,
      List<Node>? children,
    }) => Node.pane(
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
      ], instance: placedCard);
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
      Node nest(int depth) => pane(
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
            root: Node.pane(
              id: 'rail',
              columns: 4,
              children: [
                _item('a', w: 3),
                // Something with a folder's id gives way to the folder.
                _item('games', ref: 'system:app/x'),
                pane('in-rail', children: [_item('b')]),
                // A folder: docked, so off the cells of the pane it is in.
                drawnPane(folderPane('games', title: 'Games'))
                    .withValue(layoutModule.name, 'mode', 'grid')
                    .copyWith(
                      children: [
                        _item('a', x: 9, y: 2, w: 2, h: 99),
                        _item('half', x: 1),
                        cardOf('games', id: 'open', prefab: folderPrefabId),
                        // An empty node is a node like any other.
                        const Node(id: 'empty'),
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

      expect((games.id, games.name, games.isDocked), ('games', 'Games', true));
      final [a, half, open, empty, nested] = games.children;
      expect((empty.id, empty.isPane), ('empty', true));
      expect(a.id, isNot('a'));
      expect((a.x, a.y, a.w, a.h), (2, 2, 2, SizingModule.maxRows));
      expect((half.x, half.y), (null, null));
      expect(open.handed.firstOrNull, 'games');
      // Panes deeper than allowed give their contents to the last that is.
      // A docked pane starts the count again.
      expect(nested.panes, hasLength(Node.maxDepth - 1));
      expect(nested.contents.map((i) => i.handed.firstOrNull), [
        for (var depth = 2; depth <= 6; depth++) 'system:app/$depth',
      ]);
      final ids = layout.all.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('repair rounds cells, and leaves alone what has no layout around '
        'it', () {
      Node of(String id, PaneMode mode) => Node.pane(
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
      expect((free.x, free.y, free.w, free.h), (3.6, 0.3, 1.5, 0.1));
      // Kept inside the pane, in whole cells.
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
    });

    test('repair leaves what an instance does not set to its prefab', () {
      final bar = sidebarPane(
        'right',
        'right',
        children: [_item('a')],
      ).withValue(layoutModule.name, 'mode', 'grid');
      final layout = Layout(
        inbox: 'main',
        layers: [
          _home(Node.pane(id: 'root', children: [bar])),
        ],
      ).normalised();
      final repaired = layout.all.singleWhere((node) => node.id == 'right');
      expect(repaired.values(layoutModule.name), {'mode': 'grid'});
      expect(drawnPane(repaired).columns, 1);
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
                'children': [
                  {'id': 1},
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
      final layout = homeLayout(['system:app/b', 'system:app/gone'])
          .withEntities(['system:app/a', 'system:app/b'], instance: placedCard);
      // The quick actions come after it, an instance of the System pack's.
      final [item, menu] = layout.home.root.children;
      expect(menu.prefab, 'system:quick-actions');
      expect(item.children.map((i) => i.handed.firstOrNull), [
        'system:app/b',
        'system:app/a',
      ]);
      expect(layout.inbox, item.id);
      // Inside the screen's margins, on a 960 by 540 screen.
      final box = item.transform.rectIn(const Size(960, 540));
      expect(
        [box.left, box.top, box.right, box.bottom],
        [closeTo(48, 1), closeTo(79, 1), closeTo(912, 1), closeTo(513, 1)],
      );
    });
  });

  test('a pane keeps the spacing it is given, within reason', () {
    Node pane(String id, double? spacing) => Node.pane(
      id: id,
      layout: {'spacing': ?spacing},
      children: [_item('$id-a')],
    );
    final layout = Layout(
      inbox: 'a',
      layers: [
        _home(
          Node.pane(
            id: 'global',
            layout: const {'spacing': 4},
            children: [pane('a', null), pane('b', 0), pane('c', 500)],
          ),
        ),
      ],
    ).normalised();
    final panes = layout.home.root.panes.toList();
    expect(panes.map((p) => p.spacing), [4, null, 0, LayoutModule.maxSpacing]);
    // Unset, it is the usual gap, wider across than down.
    expect((panes[1].spacingX, panes[1].spacingY), (20, 16));
    expect((panes[2].spacingX, panes[2].spacingY), (0, 0));
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
    expect(
      layout
          .withEntities(['system:app/x'], instance: placedCard)
          .home
          .root
          .spacing,
      4,
    );
  });

  test('a pane keeps the padding it is given, within reason', () {
    final layout = Layout.fromJson(const {
      'v': saveVersion,
      'layers': [
        {
          'id': 'home',
          'root': {
            'id': 'global',
            'modules': {
              'style': {'padding': 24},
            },
            'children': [
              {
                'id': 'a',
                'modules': {
                  'style': {'padding': 900},
                },
              },
              {'id': 'b'},
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
              Node.pane(
                id: 'global',
                children: [
                  cardOf('games', id: 'folder', prefab: folderPrefabId),
                  _item('time', kind: textModule.name),
                  Node.pane(id: 'main'),
                  folderPane(
                    'games',
                    title: 'Games',
                    children: [_item('system:app/b')],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      // As the launcher draws it, with what docks resolved.
      final view = layoutWith(
        withDockedInstances(config.layout, systemPrefabMap),
        entities,
        systemPrefabMap,
      );
      final [folder, clock, pane, games] = view.home.root.children;

      // Handed a folder, not an entity.
      expect(config.layout.folderOf(folder), 'games');
      expect(clock.visual, textModule);
      // The entity placed nowhere turns up in the inbox pane; the removed
      // one does not.
      expect(pane.children.single.handed.firstOrNull, 'system:app/a');
      expect(games.children.single.handed.firstOrNull, 'system:app/b');
      // The folder is docked: on the layer, off its cells.
      expect(view.docked.map((p) => p.id), ['games']);
      expect(
        placeItems(view.home.root.children, 5, PaneMode.flow).last,
        const Placement(0, 0, 0, 0),
      );
    });

    test('the same entity can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'global',
          layers: [
            _home(
              Node.pane(
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
      final entries = layoutWith(
        config.layout,
        entities,
        systemPrefabMap,
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
      final left = drawnPane(sidebarPane('left', 'left'));
      final top = drawnPane(sidebarPane('top', 'top'));
      expect((left.isDocked, left.hiddenWhenClosed), (true, false));
      expect(
        (left.edge, left.openWidth, left.openHeight, left.closed),
        (BarEdge.left, 260, DockModule.fill, 96),
      );
      // Along a side it starts as a line of small rows.
      expect(left.rowHeight, LayoutModule.barRowHeight);
      expect(left.prefabRules[cardPrefabId], {'variant': 'row'});
      expect(
        (top.edge, top.openWidth, top.openHeight, top.closed),
        (BarEdge.top, DockModule.fill, 120, 0),
      );
      // It opens while it has the focus, by what is written on it.
      expect(left.on.keys, Trigger.values.skip(2));
      // A folder is hidden while closed; in the middle it is as tall as what
      // is in it.
      final folder = drawnPane(folderPane('games'));
      expect(
        (
          folder.hiddenWhenClosed,
          folder.edge,
          folder.openWidth,
          folder.openHeight,
        ),
        (true, null, 595, null),
      );
      // A word that is no dock leaves a pane on its parent's cells.
      expect(
        Node.pane(id: 'p', dock: const {'position': 'sky'}).isDocked,
        isFalse,
      );
    });

    Layout holding(List<Node> docked) => Layout(
      inbox: 'main',
      layers: [_home(Node.pane(id: 'root', children: docked))],
    ).normalised();

    test('sizes are written, read back and kept within bounds', () {
      final layout = holding([
        drawnPane(sidebarPane('right', 'right'))
            .withValue(dockModule.name, 'width', 'fill')
            .withValue(dockModule.name, 'height', 300)
            .withValue(dockModule.name, 'closed', 0),
        drawnPane(sidebarPane('bottom', 'bottom'))
            .withValue(dockModule.name, 'height', 5000)
            .withValue(dockModule.name, 'closed', -3),
        // One off an edge has no strip to show.
        drawnPane(folderPane('games')).withValue(dockModule.name, 'closed', 40),
      ]);
      final copy = Layout.fromJson(layout.toJson());
      final right = copy.pane('right')!;
      expect(
        (right.dockWidth, right.dockHeight, right.closed),
        (DockModule.fill, 300, 0),
      );
      final bottom = copy.pane('bottom')!;
      expect((bottom.dockHeight, bottom.closed), (DockModule.maxExtent, 0));
      expect(bottom.dockWidth, isNull);
      expect(copy.pane('games')!.hiddenWhenClosed, isTrue);
    });

    test('how one opens is written and read back, the usual left out', () {
      final usual = drawnPane(sidebarPane('left', 'left'));
      expect(
        (
          usual.valueOf(dockModule, 'opening'),
          usual.valueOf(dockModule, 'reveal'),
        ),
        ('expand', 'always'),
      );
      expect(usual.values(dockModule.name)!.keys, isNot(contains('opening')));

      final layout = holding([
        usual
            .withValue(dockModule.name, 'opening', 'slide')
            .withValue(dockModule.name, 'reveal', 'late'),
      ]);
      final left = Layout.fromJson(layout.toJson()).pane('left')!;
      expect(
        (
          left.valueOf(dockModule, 'opening'),
          left.valueOf(dockModule, 'reveal'),
        ),
        ('slide', 'late'),
      );

      // A word it does not know is taken as the usual.
      final odd = holding([left.withValue(dockModule.name, 'opening', 'spin')])
          .pane('left')!;
      expect(
        (odd.valueOf(dockModule, 'opening'), odd.valueOf(dockModule, 'reveal')),
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
      final pane = Node.pane(
        id: 'p',
        layout: const {'itemW': 2},
        prefabRules: rules,
        children: [
          _item('a', w: 3, h: 2),
          _item('time', kind: textModule.name, w: 4),
          Node.pane(id: 'inner', w: 5),
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
      // What the entity says is still there for when the pane stops.
      expect(pane.children.first.w, 3);
      expect(pane.children.first.overrides, isEmpty);
      expect(Node.pane(id: 'p').decides, isFalse);
      // And all of it survives being written and read.
      final copy = Node.fromJson(
        pane.withValue(layoutModule.name, 'rowHeight', 40).toJson(),
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
        layers: [_home(Node.pane(id: 'p', style: style))],
      ).normalised();
      expect(layout.home.root.style, style);
      final read = Node.fromJson(layout.home.root.toJson());
      expect(read.style, style);
      expect(read.box.corners, [0, 8, 20, 4]);
    });

    test('what is drawn is what the pane decides', () {
      final view = layoutWith(
        Layout(
          inbox: 'main',
          layers: [
            _home(
              Node.pane(
                id: 'main',
                prefabRules: const {
                  cardPrefabId: {'variant': 'row'},
                },
                children: [_item('a', ref: 'system:app/a')],
              ),
            ),
          ],
        ),
        const [Entity(id: 'system:app/a', category: appCategory, label: 'A')],
        systemPrefabMap,
      );
      expect(view.home.root.shown.first.variant, 'row');
    });
  });

  group('LauncherConfig', () {
    test('survives a JSON round trip', () {
      final config = LauncherConfig(
        layout: homeLayout(['system:app/a']).without({'system:app/b'}),
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

    test('a starting layout is not saved; the user\'s is', () {
      final start = LauncherConfig(layout: homeLayout(), ownLayout: false);
      expect(start.toJson(), isNot(contains('layout')));
      expect(LauncherConfig.fromJson(start.toJson()).ownLayout, isFalse);
      expect(start.copyWith(wallpapers: const []).ownLayout, isFalse);

      final edited = start.copyWith(layout: homeLayout(['system:app/a']));
      expect(edited.ownLayout, isTrue);
      expect(LauncherConfig.fromJson(edited.toJson()).ownLayout, isTrue);
    });

    test('a broken layout does not lose the rest', () {
      final config = LauncherConfig.fromJson(const {
        'layout': {'layers': 7},
        'wallpapers': ['/w.png'],
      });
      expect(config.wallpapers, ['/w.png']);
      expect(config.wallpaperEvery, 0);
      // The store gives it the starting layout.
      expect(config.ownLayout, isFalse);
      expect(config.layout.home.root.children, isEmpty);
    });
  });
}
