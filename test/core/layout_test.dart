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

Screen _home(Node root) => Screen(id: 'home', root: root);

void main() {
  group('placeItems', () {
    test('flow fills rows in order and wraps', () {
      final placed = placeItems(
        [_item('a'), _item('b', w: 2), _item('c'), _item('d')],
        3,
        LayoutMode.flow,
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
        LayoutMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 2),
        Placement(1, 0, 2, 1),
        Placement(1, 1, 1, 1),
        Placement(2, 1, 1, 1),
      ]);
    });

    test('an item wider than the section is cut down to fit', () {
      expect(placeItems([_item('a', w: 4)], 2, LayoutMode.flow), const [
        Placement(0, 0, 2, 1),
      ]);
    });

    test('grid keeps positions and leaves gaps', () {
      final placed = placeItems(
        [_item('a', x: 2, y: 1), _item('b', x: 0, y: 0)],
        4,
        LayoutMode.grid,
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
        LayoutMode.grid,
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
        placeItems([_item('a', x: 1, y: 1), _item('b')], 4, LayoutMode.free),
        const [Placement(0, 0, 0, 0), Placement(0, 0, 0, 0)],
      );
    });

    test('a container that scrolls across keeps its children on one row', () {
      final items = [_item('a'), _item('b', w: 2), _item('c'), _item('d')];
      final wraps = Node.layout(id: 'p', columns: 3, children: items);
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
      Node container(
        LayoutMode mode, [
        Map<String, Object?>? scroll,
        Map<String, Object?> layout = const {},
      ]) => Node.layout(id: 'p', mode: mode, scroll: scroll, layout: layout);
      const both = {'across': true, 'down': true};
      for (final mode in [LayoutMode.flow, LayoutMode.grid]) {
        // A new container on cells scrolls down.
        expect(
          (container(mode).scrollsAcross, container(mode).scrollsDown),
          (false, true),
        );
        expect(container(mode, const {}).scrollsDown, isFalse);
        expect(container(mode, both).scrollsAcross, isTrue);
      }
      // Without a layout nothing scrolls.
      expect(
        (
          container(LayoutMode.free, both).scrollsAcross,
          container(LayoutMode.free, both).scrollsDown,
        ),
        (false, false),
      );
      // A row scrolls along itself only, and so does a column.
      expect(container(LayoutMode.row).scrollsAcross, isFalse);
      expect(container(LayoutMode.column).scrollsDown, isFalse);
      expect(
        (
          container(LayoutMode.row, both).scrollsAcross,
          container(LayoutMode.row, both).scrollsDown,
        ),
        (true, false),
      );
      expect(
        (
          container(LayoutMode.column, both).scrollsAcross,
          container(LayoutMode.column, both).scrollsDown,
        ),
        (false, true),
      );
      // Scaled to its box, there is nothing to scroll.
      expect(
        container(LayoutMode.row, both, const {'fit': true}).scrollsAcross,
        isFalse,
      );
    });

    test(
      'a scroll bar is for a container that scrolls, and reads its look',
      () {
        final container = Node.layout(
          id: 'p',
          scroll: const {'down': true, 'bar': 'thumb'},
        );
        Node set(String key, Object value) =>
            container.withValue(scrollModule.name, key, value);
        expect(
          (container.scrollbar, container.scrollbarHides),
          ('thumb', false),
        );
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
      },
    );
  });

  group('containers', () {
    Node container(
      String id, {
      LayoutMode mode = LayoutMode.flow,
      List<Node>? children,
    }) => Node.layout(
      id: id,
      mode: mode,
      columns: 4,
      children: children ?? const [],
    );

    test('nest, and are found with what is in them', () {
      final root = container(
        'global',
        mode: LayoutMode.free,
        children: [
          _item('loose', ref: 'system:app/a'),
          container(
            'outer',
            children: [
              _item('in-outer', ref: 'system:app/b'),
              container(
                'inner',
                children: [_item('in-inner', ref: 'system:app/c')],
              ),
            ],
          ).sized(3, 2.5, x: 0.5, y: 1),
        ],
      );
      expect(root.containers.map((p) => p.id), ['global', 'outer', 'inner']);
      // An entity can sit in the global container, outside every other.
      expect(root.contents.map((i) => i.handed.firstOrNull), [
        'system:app/a',
        'system:app/b',
        'system:app/c',
      ]);

      final layout = Layout(
        inbox: 'inner',
        screens: [_home(root)],
      ).normalised();
      expect(layout.inbox, 'inner');
      final outer = layout.start.root.children.last;
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
      final inner = shown.container('inner')!;
      expect(inner.children.map((i) => i.handed.firstOrNull), [
        'system:app/c',
        'system:app/new',
      ]);
      // Removing an entity takes it out of every container.
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
      Node nest(int depth) => container(
        'p$depth',
        children: [
          _item('entity$depth', ref: 'system:app/$depth'),
          if (depth < 6) nest(depth + 1),
        ],
      );
      final layout = Layout(
        inbox: 'nowhere',
        screens: [
          Screen(
            id: 'over',
            root: Node.layout(
              id: 'rail',
              columns: 4,
              children: [
                _item('a', w: 3),
                // Something with a folder's id gives way to the folder.
                _item('games', ref: 'system:app/x'),
                container('in-rail', children: [_item('b')]),
                // A folder: docked, so off the cells of the container it is in.
                drawnInstance(folderOf('games', title: 'Games'))
                    .withValue(layoutModule.name, 'mode', 'grid')
                    .withValue(layoutModule.name, 'columns', 4)
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
          Screen.empty('over'),
        ],
      ).normalised();

      // One of two screens with the same id goes. The one left is what it
      // opens on, and its root the inbox.
      expect(layout.screens.map((l) => l.id), ['over']);
      expect(layout.startup.screen, 'over');
      expect(layout.inbox, layout.start.root.id);

      final rail = layout.screen('over')!.root;
      expect(rail.columns, 4);
      final [first, other, inRail, games] = rail.children;
      expect((first.id, first.w), ('a', 3));
      expect(other.id, isNot('games'));
      expect(inRail.children.single.id, 'b');

      expect((games.id, games.name, games.isDocked), ('games', 'Games', true));
      final [a, half, open, empty, nested] = games.children;
      expect((empty.id, empty.isContainer), ('empty', true));
      expect(a.id, isNot('a'));
      expect((a.x, a.y, a.w, a.h), (2, 2, 2, SizingModule.maxRows));
      expect((half.x, half.y), (null, null));
      expect(open.handed.firstOrNull, 'games');
      // Containers deeper than allowed give their contents to the last that is.
      // A docked container starts the count again.
      expect(nested.containers, hasLength(Node.maxDepth - 1));
      expect(nested.contents.map((i) => i.handed.firstOrNull), [
        for (var depth = 2; depth <= 6; depth++) 'system:app/$depth',
      ]);
      final ids = layout.all.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('repair rounds cells, and leaves alone what has no layout around '
        'it', () {
      Node of(String id, LayoutMode mode) => Node.layout(
        id: id,
        mode: mode,
        columns: 4,
        children: [_item('$id-a', x: 3.6, y: 0.3, w: 1.5, h: 0.1)],
      );
      final layout = Layout(
        inbox: 'f',
        screens: [
          _home(
            container(
              'global',
              children: [of('f', LayoutMode.free), of('g', LayoutMode.grid)],
            ),
          ),
        ],
      ).normalised();
      final [free, grid] = layout.start.root.contents.toList();
      expect((free.x, free.y, free.w, free.h), (3.6, 0.3, 1.5, 0.1));
      // Kept inside the container, in whole cells.
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
    });

    test('repair leaves what an instance does not set to its prefab', () {
      final bar = sidebarOf(
        'right',
        'right',
        children: [_item('a')],
      ).withValue(layoutModule.name, 'mode', 'grid');
      final layout = Layout(
        inbox: 'main',
        screens: [
          _home(Node.layout(id: 'root', children: [bar])),
        ],
      ).normalised();
      final repaired = layout.all.singleWhere((node) => node.id == 'right');
      expect(repaired.values(layoutModule.name), {'mode': 'grid'});
      expect(drawnInstance(repaired).columns, 1);
    });

    test('rejects what is not a layout', () {
      expect(
        () => Layout.fromJson(const {'screens': 'no'}),
        throwsFormatException,
      );
      expect(
        () => Layout.fromJson(const {
          'screens': [
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
    test('a new home screen is one container as tall as the screen', () {
      final layout = homeLayout(['system:app/b', 'system:app/gone'])
          .withEntities(['system:app/a', 'system:app/b'], instance: placedCard);
      // The quick actions come after it, an instance of the System pack's.
      final [item, menu] = layout.start.root.children;
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

  test('a container keeps the spacing it is given, within reason', () {
    Node container(String id, double? spacing) => Node.layout(
      id: id,
      layout: {'spacing': ?spacing},
      children: [_item('$id-a')],
    );
    final layout = Layout(
      inbox: 'a',
      screens: [
        _home(
          Node.layout(
            id: 'global',
            layout: const {'spacing': 4},
            children: [
              container('a', null),
              container('b', 0),
              container('c', 500),
            ],
          ),
        ),
      ],
    ).normalised();
    final containers = layout.start.root.containers.toList();
    expect(containers.map((p) => p.spacing), [
      4,
      null,
      0,
      LayoutModule.maxSpacing,
    ]);
    // Unset, it is the usual gap, wider across than down.
    expect((containers[1].spacingX, containers[1].spacingY), (20, 16));
    expect((containers[2].spacingX, containers[2].spacingY), (0, 0));
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
    expect(
      layout
          .withEntities(['system:app/x'], instance: placedCard)
          .start
          .root
          .spacing,
      4,
    );
  });

  test('a container keeps the padding it is given, within reason', () {
    final layout = Layout.fromJson(const {
      'v': saveVersion,
      'screens': [
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
    expect(layout.start.root.containers.map((p) => p.box.padding), [
      24,
      80,
      null,
    ]);
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
  });

  group('resolveLayout', () {
    final entities = [_entity('a'), _entity('b'), _entity('c')];

    test('matches items to entities, folders, widgets and containers', () {
      final config = LauncherConfig(
        iconOverrides: {'node:games': '/games.png'},
        layout: Layout(
          inbox: 'main',
          removed: const {'system:app/c'},
          screens: [
            _home(
              Node.layout(
                id: 'global',
                children: [
                  cardOf('games', id: 'folder', prefab: folderPrefabId),
                  _item('time', kind: textModule.name),
                  Node.layout(id: 'main'),
                  folderOf(
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
      final [folder, clock, container, games] = view.start.root.children;

      // Handed a node, not an entity.
      expect(config.layout.node(folder.handed.single)?.id, 'games');
      expect(clock.visual, textModule);
      // The entity placed nowhere turns up in the inbox container; the removed
      // one does not.
      expect(container.children.single.handed.firstOrNull, 'system:app/a');
      // Under the folder's heading.
      expect(
        games.children.last.children.single.handed.firstOrNull,
        'system:app/b',
      );
      // The folder is docked: on the layer, off its cells.
      expect(view.docked.map((p) => p.id), ['games']);
      expect(
        placeItems(view.start.root.children, 5, LayoutMode.flow).last,
        const Placement(0, 0, 0, 0),
      );
    });

    test('the same entity can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'global',
          screens: [
            _home(
              Node.layout(
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
      ).start.root.children.where((e) => e.isInstance);
      expect(entries.map((e) => e.handed.firstOrNull), [
        'system:app/a',
        'system:app/a',
        'system:app/b',
        'system:app/c',
      ]);
    });
  });

  group('sidebars and what containers decide', () {
    test('a sidebar is a container docked to an edge, with its usual size', () {
      final left = drawnInstance(sidebarOf('left', 'left'));
      final top = drawnInstance(sidebarOf('top', 'top'));
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
      expect(left.on.keys, [Trigger.focus, Trigger.blur]);
      // A folder is hidden while closed; in the middle it is as tall as what
      // is in it.
      final folder = drawnInstance(folderOf('games'));
      expect(
        (
          folder.hiddenWhenClosed,
          folder.edge,
          folder.openWidth,
          folder.openHeight,
        ),
        (true, null, 595, null),
      );
      // A word that is no dock leaves a container on its parent's cells.
      expect(
        Node.layout(id: 'p', dock: const {'position': 'sky'}).isDocked,
        isFalse,
      );
    });

    Layout holding(List<Node> docked) => Layout(
      inbox: 'main',
      screens: [_home(Node.layout(id: 'root', children: docked))],
    ).normalised();

    test('sizes are written, read back and kept within bounds', () {
      final layout = holding([
        drawnInstance(sidebarOf('right', 'right'))
            .withValue(dockModule.name, 'width', 'fill')
            .withValue(dockModule.name, 'height', 300)
            .withValue(dockModule.name, 'closed', 0),
        drawnInstance(sidebarOf('bottom', 'bottom'))
            .withValue(dockModule.name, 'height', 5000)
            .withValue(dockModule.name, 'closed', -3),
        // One off an edge has no strip to show.
        drawnInstance(folderOf('games'))
            .withValue(dockModule.name, 'closed', 40),
      ]);
      final copy = Layout.fromJson(layout.toJson());
      final right = copy.container('right')!;
      expect(
        (right.dockWidth, right.dockHeight, right.closed),
        (DockModule.fill, 300, 0),
      );
      final bottom = copy.container('bottom')!;
      expect((bottom.dockHeight, bottom.closed), (DockModule.maxExtent, 0));
      expect(bottom.dockWidth, isNull);
      expect(copy.container('games')!.hiddenWhenClosed, isTrue);
    });

    test('how one opens is written and read back, the usual left out', () {
      final usual = drawnInstance(sidebarOf('left', 'left'));
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
      final left = Layout.fromJson(layout.toJson()).container('left')!;
      expect(
        (
          left.valueOf(dockModule, 'opening'),
          left.valueOf(dockModule, 'reveal'),
        ),
        ('slide', 'late'),
      );

      // A word it does not know is taken as the usual.
      final odd = holding([left.withValue(dockModule.name, 'opening', 'spin')])
          .container('left')!;
      expect(
        (odd.valueOf(dockModule, 'opening'), odd.valueOf(dockModule, 'reveal')),
        ('expand', 'late'),
      );
    });

    test(
      'a container decides for its entities without changing what they say',
      () {
        const rules = {
          cardPrefabId: {
            'variant': 'row',
            'overrides': {
              'name': {
                'modules': {
                  'visibility': {'visible': false},
                },
              },
            },
          },
        };
        final container = Node.layout(
          id: 'p',
          layout: const {'itemW': 2},
          prefabRules: rules,
          children: [
            _item('a', w: 3, h: 2),
            _item('time', kind: textModule.name, w: 4),
            Node.layout(id: 'inner', w: 5),
          ],
        );
        final [entity, widget, inner] = container.shown;
        expect((entity.w, entity.h), (2, 2));
        expect(entity.variant, 'row');
        expect(entity.overrides, {
          'name': {
            'modules': {
              'visibility': {'visible': false},
            },
          },
        });
        // Only entities and folders are decided for.
        expect((widget.w, inner.w), (4, 5));
        // What the entity says is still there for when the container stops.
        expect(container.children.first.w, 3);
        expect(container.children.first.overrides, isEmpty);
        expect(Node.layout(id: 'p').decides, isFalse);
        // And all of it survives being written and read.
        final copy = Node.fromJson(
          container.withValue(layoutModule.name, 'rowHeight', 40).toJson(),
        );
        expect(copy.prefabRules, rules);
        expect((copy.itemW, copy.rowHeight), (2, 40));
      },
    );

    test('a container keeps its look through being written and read', () {
      const style = {
        'background': '#101820cc',
        'radius': [0, 8, 20, 4],
        'color': '#ffd700',
      };
      final layout = Layout(
        inbox: 'p',
        screens: [_home(Node.layout(id: 'p', style: style))],
      ).normalised();
      expect(layout.start.root.style, style);
      final read = Node.fromJson(layout.start.root.toJson());
      expect(read.style, style);
      expect(read.box.corners, [0, 8, 20, 4]);
    });

    test('what is drawn is what the container decides', () {
      final view = layoutWith(
        Layout(
          inbox: 'main',
          screens: [
            _home(
              Node.layout(
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
      expect(view.start.root.shown.first.variant, 'row');
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
        'layout': {'screens': 7},
        'wallpapers': ['/w.png'],
      });
      expect(config.wallpapers, ['/w.png']);
      expect(config.wallpaperEvery, 0);
      // The store gives it the starting layout.
      expect(config.ownLayout, isFalse);
      expect(config.layout.start.root.children, isEmpty);
    });
  });
}
