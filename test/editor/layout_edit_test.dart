import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/editing.dart';

import '../support/packs.dart';

Node entity(String id, {double w = 1, double h = 1, double? x, double? y}) =>
    cardOf('system:app/$id', id: id, w: w, h: h, x: x, y: y);

/// The Dock fields [pane] is offered.
List<Field> dockFieldsOf(Node pane) => [
  for (final field in dockModule.fields)
    if (field.when?.call(pane.values(dockModule.name) ?? const {}) ?? true)
      field,
];

Layout home(Node root, {Set<String> removed = const {}}) => Layout(
  inbox: root.id,
  removed: removed,
  layers: [Layer(id: Layout.homeId, root: root)],
);

List<String> ids(Layout layout, String pane) => [
  for (final item in findPane(layout, pane)!.pane.children) item.id,
];

(double?, double?) at(Layout layout, String id) {
  for (final pane in layout.home.root.panes) {
    for (final item in pane.children) {
      if (item.id == id) return (item.x, item.y);
    }
  }
  throw StateError('$id is nowhere');
}

void main() {
  group('settle', () {
    test('the fixed item gets its cell and what was there moves aside', () {
      final settled = settle(
        [
          entity('a', x: 0, y: 0),
          entity('b', x: 1, y: 0),
          entity('new', x: 0, y: 0),
        ],
        3,
        fixed: 'new',
      );
      expect((settled[2].x, settled[2].y), (0, 0));
      expect((settled[1].x, settled[1].y), (1, 0));
      // The nearest free cell to where it was.
      expect((settled[0].x, settled[0].y), (0, 1));
    });

    test('an item with no wish takes the first free cell', () {
      final settled = settle([entity('a', x: 0, y: 0), entity('b')], 2);
      expect((settled[1].x, settled[1].y), (1, 0));
    });

    test('nothing is wider than the pane or left overlapping', () {
      final settled = settle(
        [entity('a', w: 5, x: 3, y: 0), entity('b', w: 2, h: 2, x: 0, y: 0)],
        3,
        fixed: 'a',
      );
      expect((settled[0].w, settled[0].x, settled[0].y), (3, 0, 0));
      expect(settled[1].y, 1);
    });
  });

  group('dropItem', () {
    final flow = home(
      Node.pane(id: 'p', children: [entity('a'), entity('b'), entity('c')]),
    );

    test('goes in front of an item of a pane that flows, or to its end', () {
      expect(
        ids(dropItem(flow, entity('n'), const Drop('p', before: 'b')), 'p'),
        ['a', 'n', 'b', 'c'],
      );
      expect(ids(dropItem(flow, entity('n'), const Drop('p')), 'p'), [
        'a',
        'b',
        'c',
        'n',
      ]);
    });

    test('moves an item that is already there instead of adding it', () {
      final moved = dropItem(flow, entity('c'), const Drop('p', before: 'a'));
      expect(ids(moved, 'p'), ['c', 'a', 'b']);
    });

    test('takes the asked cell of a grid and pushes aside what was there', () {
      final grid = home(
        Node.pane(
          id: 'p',
          mode: PaneMode.grid,
          columns: 4,
          children: [entity('a', x: 1, y: 0)],
        ),
      );
      final dropped = dropItem(grid, entity('n'), const Drop('p', x: 1, y: 0));
      expect(at(dropped, 'n'), (1, 0));
      expect(at(dropped, 'a'), isNot((1, 0)));
      // And survives the TV's own repairs unchanged.
      expect(at(dropped.normalised(), 'n'), (1, 0));
    });

    test('lands where asked without a layout, pinned where it is put', () {
      final free = home(
        Node.pane(id: 'p', mode: PaneMode.free, children: [entity('a')]),
      );
      const rect = Rect.fromLTWH(100, 40, 200, 90);
      final dropped = dropItem(
        free,
        entity('n'),
        const Drop('p', rect: rect, size: Size(800, 400)),
      );
      final n = findItems(dropped, {'n'}).single.item;
      expect(n.transform, NodeTransform.at(rect));
      expect(n.transform.rectIn(const Size(400, 200)), rect);

      // One anchored to stretch keeps its anchors and is moved by its offsets.
      const stretched = NodeTransform(minX: 0.5, maxX: 1);
      final moved = placeItem(
        home(
          Node.pane(
            id: 'p',
            mode: PaneMode.free,
            children: [entity('s').copyWith(transform: stretched)],
          ),
        ),
        's',
        rect,
        const Size(800, 400),
      );
      final s = findItems(moved, {'s'}).single.item.transform;
      expect((s.minX, s.maxX), (0.5, 1));
      expect(s.rectIn(const Size(800, 400)), rect);
    });

    test('moves an item from one pane into another inside it', () {
      final nested = home(
        Node.pane(
          id: 'p',
          children: [
            entity('a'),
            Node.pane(id: 'inner', w: 3, h: 2),
          ],
        ),
      );
      final moved = dropItem(nested, entity('a'), const Drop('inner'));
      expect(ids(moved, 'p'), ['inner']);
      expect(ids(moved, 'inner'), ['a']);
    });

    test('an entity that is placed is no longer removed', () {
      final layout = home(
        Node.pane(id: 'p'),
        removed: {'system:app/n', 'system:app/z'},
      );
      expect(dropItem(layout, entity('n'), const Drop('p')).removed, {
        'system:app/z',
      });
    });

    test('a new folder brings its pane with it, docked on the home layer', () {
      final dropped = dropItem(
        flow,
        cardOf('f', id: 'i', prefab: folderPrefabId),
        const Drop('p'),
        opens: folderPane('f', title: 'Games'),
      );
      final folder = dropped.pane('f')!;
      expect((folder.name, folder.hiddenWhenClosed), ('Games', true));
      expect(dropped.home.root.children.last, same(folder));
      // The TV keeps the card because the folder it opens exists.
      expect(ids(dropped.normalised(), 'p'), contains('i'));
    });
  });

  group('refusal', () {
    Node nest(int levels, String id) =>
        Node.pane(id: id, children: [if (levels > 1) nest(levels - 1, '$id+')]);

    test('only panes are ever refused', () {
      final layout = home(nest(Node.maxDepth, 'p'));
      expect(refusal(layout, entity('a'), 'p+++'), isNull);
    });

    test('a pane cannot go inside itself or deeper than panes go', () {
      final layout = home(nest(Node.maxDepth, 'p'));
      final inner = layout.home.root.children.single;
      expect(refusal(layout, inner, 'p++'), contains('inside itself'));
      expect(refusal(layout, Node.pane(id: 'new'), 'p+++'), contains('nested'));
      expect(refusal(layout, Node.pane(id: 'new'), 'p++'), isNull);
    });

    test('a sidebar takes panes like anywhere else, however deep it is', () {
      // Docked at the bottom of the deepest nest, it still counts from one.
      Node deep(int levels) => Node.pane(
        id: 'p$levels',
        children: [
          if (levels > 1) deep(levels - 1) else sidebarPane('left', 'left'),
        ],
      );
      final layout = home(deep(Node.maxDepth));
      final found = findPane(layout, 'left')!;
      expect((found.depth, found.dock?.id), (1, 'left'));
      expect(refusal(layout, Node.pane(id: 'new'), 'left'), isNull);
      expect(refusal(layout, Node.pane(id: 'new'), 'p1'), isNotNull);
    });

    test('a docked pane takes no cell and is told what it is in', () {
      final layout = home(
        Node.pane(
          id: 'p',
          mode: PaneMode.grid,
          columns: 2,
          children: [
            entity('a', x: 0, y: 0),
            sidebarPane('left', 'left').copyWith(children: [entity('b')]),
            entity('c', x: 0, y: 0),
          ],
        ),
      );
      // Settling moves what collides, and leaves the sidebar alone.
      final [a, bar, c] = settle(layout.home.root.children, 2);
      expect((a.x, a.y, c.x, c.y), (0, 0, 1, 0));
      expect((bar.id, bar.x), ('left', null));
      final [inRoot, inBar] = findItems(layout, {'a', 'b'});
      expect((inRoot.dock, inBar.dock?.id), (null, 'left'));
      expect(inBar.layer.id, Layout.homeId);
    });
  });

  group('removeItem', () {
    test('notes an entity as removed once it is nowhere', () {
      final layout = home(
        Node.pane(
          id: 'p',
          children: [
            entity('a'),
            cardOf('system:app/a', id: 'again'),
          ],
        ),
      );
      final once = removeItem(layout, 'a');
      expect(ids(once, 'p'), ['again']);
      expect(once.removed, isEmpty);
      expect(removeItem(once, 'again').removed, {'system:app/a'});
    });

    test('a pane goes with everything in it', () {
      final layout = home(
        Node.pane(
          id: 'p',
          children: [
            entity('a'),
            Node.pane(id: 'inner', children: [entity('b'), entity('c')]),
          ],
        ),
      );
      final removed = removeItem(layout, 'inner');
      expect(ids(removed, 'p'), ['a']);
      expect(removed.removed, {'system:app/b', 'system:app/c'});
    });
  });

  group('editing what is selected', () {
    final layout = home(
      Node.pane(
        id: 'p',
        mode: PaneMode.grid,
        columns: 4,
        children: [
          entity('a', x: 0, y: 0),
          entity('b', x: 1, y: 0),
          Node.pane(
            id: 'inner',
            children: [entity('c'), entity('d', w: 2)],
            w: 4,
            h: 2,
            x: 0,
            y: 1,
          ),
        ],
      ),
    );

    test('finds items with the pane they are in, wherever they are', () {
      final found = findItems(layout, {'a', 'd', 'gone'});
      expect(
        [for (final one in found) (one.item.id, one.parent.id)],
        [('a', 'p'), ('d', 'inner')],
      );
    });

    test('changes only the items named', () {
      final changed = changeItems(layout, {
        'a',
        'c',
      }, (item, _) => item.copyWith(name: 'changed'));
      expect(
        [
          for (final one in findItems(changed, {'a', 'b', 'c'}))
            one.item.name.isNotEmpty,
        ],
        [true, false, true],
      );
    });

    test('a resized item keeps its cell and its neighbour moves aside', () {
      final resized = resizeItems(layout, {'a'}, w: 2);
      final a = findItems(resized, {'a'}).single.item;
      expect((a.w, a.x, a.y), (2, 0, 0));
      expect(at(resized, 'b'), isNot((1, 0)));
      // Never wider than the pane it is in.
      expect(
        findItems(resizeItems(layout, {'a'}, w: 9), {'a'}).single.item.w,
        4,
      );
    });

    test('an item is given a new place and size at once', () {
      // Its left edge pulled one cell to the left... there is none: over b.
      final reshaped = reshapeItem(layout, 'b', x: 0, y: 0, w: 2, h: 1);
      final b = findItems(reshaped, {'b'}).single.item;
      expect((b.x, b.y, b.w), (0, 0, 2));
      expect(at(reshaped, 'a'), isNot((0, 0)));
      // Where things flow, only the size is taken.
      final flowed = reshapeItem(layout, 'd', x: 3, y: 3, w: 1, h: 2);
      final d = findItems(flowed, {'d'}).single.item;
      expect((d.x, d.y, d.w, d.h), (null, null, 1, 2));
    });

    test('a transform is set a part at a time, by the pane it is in', () {
      // Where things have places they are offered; where they flow, not.
      List<String> offered(String id) => [
        for (final option in SizingModule.fieldsIn([
          findItems(layout, {id}).single.parent,
        ], findItems(layout, {id}).single.parent.reach))
          option.key,
      ];
      expect(offered('a'), ['w', 'h', 'x', 'y']);
      expect(offered('d'), ['w', 'h']);

      final wider = transformItems(layout, {'a'}, 'w', 2);
      expect(findItems(wider, {'a'}).single.item.w, 2);
      // A column is given: its neighbour there moves aside.
      final moved = transformItems(layout, {'a'}, 'x', 1);
      expect(at(moved, 'a'), (1, 0));
      expect(at(moved, 'b'), isNot((1, 0)));
      // A place taken away is a column and a row gone together.
      final loose = findItems(transformItems(layout, {'a'}, 'y', null), {
        'a',
      }).single.item;
      expect((loose.x, loose.y), (null, null));
    });

    test('several are resized together, each in its own pane', () {
      final resized = resizeItems(layout, {'a', 'c'}, h: 2);
      expect(
        [
          for (final one in findItems(resized, {'a', 'c', 'd'})) one.item.h,
        ],
        [2, 2, 1],
      );
    });

    test('a pane keeps things where they were when its placement changes', () {
      final inner = layout.home.root.children.last;
      final grid = withMode(inner, PaneMode.grid);
      expect(
        [for (final item in grid.children) (item.id, item.x, item.y)],
        [('c', 0, 0), ('d', 1, 0)],
      );
      // And back in order by where they are, not by how they were listed.
      final swapped = grid.copyWith(
        children: [
          grid.children[1].sized(2, 1, x: 0, y: 0),
          grid.children[0].sized(1, 1, x: 2, y: 0),
        ],
      );
      expect(
        [for (final item in withMode(swapped, PaneMode.flow).children) item.id],
        ['d', 'c'],
      );
    });

    test('fewer columns narrow and move what no longer fits', () {
      final narrowed = withColumns(layout.home.root, 2);
      final inner = narrowed.children.last;
      expect((inner.w, inner.x), (2, 0));
      expect(narrowed.columns, 2);
    });
  });

  test('deleting a folder takes its entities and what was in it', () {
    final layout = home(
      Node.pane(
        id: 'p',
        children: [
          entity('a'),
          cardOf('f', id: 'opens', prefab: folderPrefabId),
          folderPane('f').copyWith(
            children: [
              entity('b'),
              cardOf('system:app/a', id: 'a2'),
            ],
          ),
        ],
      ),
    );
    final deleted = removeItem(layout, 'f');
    expect(deleted.pane('f'), isNull);
    expect(ids(deleted, 'p'), ['a']);
    // Only what is now nowhere counts as removed.
    expect(deleted.removed, {'system:app/b'});
    expect(removeItem(layout, 'nothing').toJson(), layout.toJson());
  });

  test('counts how often each entity is on the TV', () {
    final layout = home(
      Node.pane(
        id: 'p',
        children: [
          entity('a'),
          cardOf('system:app/a', id: 'again'),
          drawn('w', textModule.name),
        ],
      ),
    );
    expect(placedCounts(layout), {'system:app/a': 2});
  });

  group('templates', () {
    final folder = systemPrefab(folderTemplateId);
    final sidebar = systemPrefab(sidebarTemplateId);

    test('any pack\'s template is read from its data alone', () {
      // Another pack's: a drawer down the right, and across the bottom.
      final drawer = Prefab(
        id: 'acme:drawer',
        name: 'Drawer',
        template: true,
        root: Node.pane(
          id: 'root',
          dock: const {'position': 'right', 'closed': 40},
        ),
        variants: {
          'down': const PrefabVariant('Down'),
          'shelf': const PrefabVariant('Shelf', {
            'root': {
              'modules': {
                'dock': {'position': 'bottom'},
                'layout': {'columns': 9},
              },
            },
          }),
        },
      );
      // The variant that docks there, else on the same side of the axis.
      expect(variantFor(drawer, 'right'), 'down');
      expect(variantFor(drawer, 'left'), 'down');
      expect(variantFor(drawer, 'top'), 'shelf');
      final made = paneFrom(drawer, 'bar', dock: 'top');
      expect((made.dock, made.columns, made.template), ('top', 9, drawer.id));
      final layout = homeLayout().withPane(
        'home/root',
        (root) => root.copyWith(children: [...root.children, made]),
      );
      expect(madeBy(drawer, layout).single.id, 'bar');
      expect(madeBy(systemPrefab(sidebarTemplateId), layout), isEmpty);
    });

    test('make plain copies, not instances', () {
      final made = paneFrom(folder, 'games');
      expect(
        (made.isPane, made.isInstance, made.name, made.dock),
        (true, false, 'Folder', 'center'),
      );
      expect(made.closeOnPress, isTrue);
      expect(made.style, folder.root.style);
      expect(made.on, folder.root.on);
      // It records what it was copied from.
      expect(made.template, folderTemplateId);
      expect(Node.fromJson(made.toJson()).template, folderTemplateId);
      // Down a side it is a column of rows; across, a row.
      final left = paneFrom(sidebar, 'l', dock: 'left');
      final top = paneFrom(sidebar, 't', dock: 'bottom');
      expect((left.dock, left.columns, left.closed), ('left', 1, 96));
      expect(left.prefabRules.keys, [cardPrefabId, folderPrefabId]);
      expect((top.dock, top.columns, top.closed), ('bottom', 8, 0));
      expect(left.closeOnPress, isFalse);
    });

    test('give what they made their look, keeping what is in it', () {
      final restyled = folder.copyWith(
        root: folder.root
            .styled(const {'background': '#ff0000ff'})
            .withValue(dockModule.name, 'opening', 'fade'),
      );
      final layout = homeLayout().withPane(
        'home/root',
        (root) => root.copyWith(
          children: [
            ...root.children,
            folderPane(
              'games',
              title: 'Games',
            ).copyWith(children: [entity('a')]),
            withDock(folderPane('near'), DockModule.inline),
            sidebarPane('left', 'left'),
          ],
        ),
      );
      expect(madeBy(restyled, layout).map((pane) => pane.id), [
        'games',
        'near',
      ]);
      final applied = withTemplateApplied(layout, restyled);
      final games = applied.pane('games')!;
      expect(games.style, {'background': '#ff0000ff'});
      expect(games.valueOf(dockModule, 'opening'), 'fade');
      expect((games.name, games.children.single.id), ('Games', 'a'));
      // Each stays where it docks and takes the template's chains.
      final near = applied.pane('near')!;
      expect(near.dock, DockModule.inline);
      expect(near.on, folder.root.on);
      // One copied from another template is left alone.
      expect(applied.pane('left')!.toJson(), layout.pane('left')!.toJson());
    });
  });

  group('docking', () {
    test('an edge is free with nothing docked, or an empty pane', () {
      final template = systemPrefab(sidebarTemplateId);
      final layout = withBar(
        Layout.fromJson(const {}).normalised(),
        'top',
        template,
      );
      final top = barOn(layout, 'top')!;
      expect((top.id, top.dock, top.closed), ('top', 'top', 0));
      // Asked for again, it is the one there is.
      expect(withBar(layout, 'top', template), same(layout));
      final full = withBar(layout, 'left', template).withPane(
        'left',
        (pane) => pane.copyWith(children: [cardOf('x', id: 'a')]),
      );
      expect(freeEdges(layout), barEdges);
      expect(freeEdges(full), ['right', 'top', 'bottom']);
      // Whatever is docked at an edge takes it once it holds something.
      final folder = folderPane('f')
          .withValue(dockModule.name, 'position', 'right');
      Layout withFolder(Node folder) => full.withPane(
        full.home.root.id,
        (root) => root.copyWith(children: [...root.children, folder]),
      );
      expect(freeEdges(withFolder(folder)), ['right', 'top', 'bottom']);
      expect(freeEdges(withFolder(folder.copyWith(children: [entity('a')]))), [
        'top',
        'bottom',
      ]);

      // Docking sets the dock and nothing more; undocked it is as it was,
      // back on the cells.
      final plain = Node.pane(id: 'p', columns: 3, w: 4, x: 1, y: 2);
      final docked = withRule(plain, 'dock', 'position', 'top');
      expect(
        (docked.edge, docked.closed, docked.hiddenWhenClosed),
        (BarEdge.top, null, true),
      );
      expect(docked.on, isEmpty);
      expect((docked.columns, docked.w, docked.x), (3, 4, 1));
      final back = withRule(
        withRule(withRule(docked, 'dock', 'width', 300), 'dock', 'closed', 8),
        'dock',
        'position',
        null,
      );
      expect(back.toJson(), plain.toJson());
      // Every pane has the same choices; the strip is for an edge.
      for (final pane in [plain, docked, folder]) {
        expect(dockFieldsOf(pane).first.choices.keys, DockModule.positions);
        expect(dockFieldsOf(pane).first.unset, 'None');
      }
      expect(dockFieldsOf(plain).map((rule) => rule.key), ['position']);
      expect(dockFieldsOf(docked).map((rule) => rule.key), contains('closed'));
      final centred = withRule(folder, 'dock', 'position', 'center');
      expect(
        dockFieldsOf(centred).map((rule) => rule.key),
        isNot(contains('closed')),
      );
      // Moved into what opens it, its chains stay its own.
      expect(
        withRule(folder, 'dock', 'position', DockModule.inline).on,
        folder.on,
      );
      expect(
        withRule(folder, 'dock', 'width', DockModule.fill).dockWidth,
        DockModule.fill,
      );
    });

    test('a pane that stops scrolling across takes its children back', () {
      final pane = Node.pane(
        id: 'p',
        mode: PaneMode.grid,
        columns: 3,
        scroll: const {'across': true},
        children: [entity('a', x: 0, y: 0), entity('b', w: 2, x: 6, y: 0)],
      );
      // Past its own columns while it scrolls, whatever their number.
      expect(withRule(pane, 'layout', 'columns', 2).children.last.x, 6);
      final dropped = dropItem(
        home(pane),
        entity('c'),
        const Drop('p', x: 9, y: 0),
      );
      expect(findPane(dropped, 'p')!.pane.children.last.x, 9);

      final back = withRule(pane, 'scroll', 'across', null);
      expect(back.scroll.containsKey('across'), isFalse);
      expect(
        [for (final item in back.children) (item.x, item.y)],
        [(0, 0), (1, 0)],
      );
    });

    test('only an edge within reach takes it, the nearest free one', () {
      const all = barEdges;
      expect(edgeNear(480, 270, 960, 540, all), isNull);
      expect(edgeNear(20, 270, 960, 540, all), 'left');
      expect(edgeNear(950, 270, 960, 540, all), 'right');
      expect(edgeNear(30, 10, 960, 540, all), 'top');
      // The corner's nearer edge is taken: the other one gets it.
      expect(edgeNear(30, 10, 960, 540, ['left', 'bottom']), 'left');
      expect(edgeNear(20, 270, 960, 540, ['right']), isNull);
    });
  });
}
