import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/layout_edit.dart';

LayoutItem entity(
  String id, {
  double w = 1,
  double h = 1,
  double? x,
  double? y,
}) => LayoutItem(
  id: id,
  kind: ItemKind.prefab,
  ref: cardPrefabId,
  vars: {'source': Variable('app:$id')},
  w: w,
  h: h,
  x: x,
  y: y,
);

Layout home(Pane root, {Set<String> removed = const {}}) => Layout(
  inbox: root.id,
  removed: removed,
  panels: [Panel(id: Layout.homeId, root: root)],
);

List<String> ids(Layout layout, String pane) => [
  for (final item in findPane(layout, pane)!.pane.items) item.id,
];

(double?, double?) at(Layout layout, String id) {
  for (final pane in layout.home.root.panes) {
    for (final item in pane.items) {
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
      Pane(id: 'p', items: [entity('a'), entity('b'), entity('c')]),
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
        Pane(
          id: 'p',
          mode: PaneMode.grid,
          columns: 4,
          items: [entity('a', x: 1, y: 0)],
        ),
      );
      final dropped = dropItem(grid, entity('n'), const Drop('p', x: 1, y: 0));
      expect(at(dropped, 'n'), (1, 0));
      expect(at(dropped, 'a'), isNot((1, 0)));
      // And survives the TV's own repairs unchanged.
      expect(at(dropped.normalised(), 'n'), (1, 0));
    });

    test('lands where asked in a free pane, kept inside its width', () {
      final free = home(
        Pane(
          id: 'p',
          mode: PaneMode.free,
          columns: 4,
          items: [entity('a', x: 0, y: 0)],
        ),
      );
      final dropped = dropItem(
        free,
        entity('n', w: 2),
        const Drop('p', x: 3, y: 0),
      );
      expect(at(dropped, 'n'), (2, 0));
      // With nowhere asked for, under what is there.
      expect(at(dropItem(free, entity('m'), const Drop('p')), 'm'), (0, 1));
    });

    test('moves an item from one pane into another inside it', () {
      final nested = home(
        Pane(
          id: 'p',
          items: [
            entity('a'),
            LayoutItem.pane(const Pane(id: 'inner'), w: 3, h: 2),
          ],
        ),
      );
      final moved = dropItem(nested, entity('a'), const Drop('inner'));
      expect(ids(moved, 'p'), ['pane-inner']);
      expect(ids(moved, 'inner'), ['a']);
    });

    test('an entity that is placed is no longer removed', () {
      final layout = home(const Pane(id: 'p'), removed: {'app:n', 'app:z'});
      expect(dropItem(layout, entity('n'), const Drop('p')).removed, {'app:z'});
    });

    test('a new folder brings its popup with it', () {
      final folder = Panel(
        id: 'f',
        title: 'Games',
        root: const Pane(id: 'f/root'),
      );
      final dropped = dropItem(
        flow,
        LayoutItem.of('f', id: 'i', prefab: folderPrefabId),
        const Drop('p'),
        panel: folder,
      );
      expect(dropped.panel('f')?.title, 'Games');
      // The TV keeps the entity because the popup it opens exists.
      expect(ids(dropped.normalised(), 'p'), contains('i'));
    });
  });

  group('refusal', () {
    Pane nest(int levels, String id) => Pane(
      id: id,
      items: [if (levels > 1) LayoutItem.pane(nest(levels - 1, '$id+'))],
    );

    test('only panes are ever refused', () {
      final layout = home(nest(Pane.maxDepth, 'p'));
      expect(refusal(layout, entity('a'), 'p+++'), isNull);
    });

    test('a pane cannot go inside itself or deeper than panes go', () {
      final layout = home(nest(Pane.maxDepth, 'p'));
      final inner = layout.home.root.items.single;
      expect(refusal(layout, inner, 'p++'), contains('inside itself'));
      expect(
        refusal(layout, LayoutItem.pane(const Pane(id: 'new')), 'p+++'),
        contains('nested'),
      );
      expect(
        refusal(layout, LayoutItem.pane(const Pane(id: 'new')), 'p++'),
        isNull,
      );
    });

    test('a sidebar takes panes like anywhere else', () {
      final layout = Layout(
        inbox: 'p',
        panels: [
          Panel(
            id: Layout.homeId,
            root: const Pane(id: 'p'),
          ),
          Panel.empty(Layout.leftId),
        ],
      );
      expect(
        refusal(
          layout,
          LayoutItem.pane(const Pane(id: 'new')),
          Panel.rootId(Layout.leftId),
        ),
        isNull,
      );
    });
  });

  group('removeItem', () {
    test('notes an entity as removed once it is nowhere', () {
      final layout = home(
        Pane(
          id: 'p',
          items: [
            entity('a'),
            const LayoutItem(
              id: 'again',
              kind: ItemKind.prefab,
              ref: cardPrefabId,
              vars: {'source': Variable('app:a')},
            ),
          ],
        ),
      );
      final once = removeItem(layout, 'a');
      expect(ids(once, 'p'), ['again']);
      expect(once.removed, isEmpty);
      expect(removeItem(once, 'again').removed, {'app:a'});
    });

    test('a pane goes with everything in it', () {
      final layout = home(
        Pane(
          id: 'p',
          items: [
            entity('a'),
            LayoutItem.pane(
              Pane(id: 'inner', items: [entity('b'), entity('c')]),
            ),
          ],
        ),
      );
      final removed = removeItem(layout, 'pane-inner');
      expect(ids(removed, 'p'), ['a']);
      expect(removed.removed, {'app:b', 'app:c'});
    });
  });

  group('editing what is selected', () {
    final layout = home(
      Pane(
        id: 'p',
        mode: PaneMode.grid,
        columns: 4,
        items: [
          entity('a', x: 0, y: 0),
          entity('b', x: 1, y: 0),
          LayoutItem.pane(
            Pane(id: 'inner', items: [entity('c'), entity('d', w: 2)]),
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
      }, (item, _) => item.copyWith(options: const {'layout': 'row'}));
      expect(
        [
          for (final one in findItems(changed, {'a', 'b', 'c'}))
            one.item.options.isNotEmpty,
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
        for (final option in transformOptions([
          findItems(layout, {id}).single.parent,
        ]))
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
      final inner = layout.home.root.items.last.pane!;
      final grid = withMode(inner, PaneMode.grid);
      expect(
        [for (final item in grid.items) (item.id, item.x, item.y)],
        [('c', 0, 0), ('d', 1, 0)],
      );
      // And back in order by where they are, not by how they were listed.
      final swapped = grid.copyWith(
        items: [
          grid.items[1].sized(2, 1, x: 0, y: 0),
          grid.items[0].sized(1, 1, x: 2, y: 0),
        ],
      );
      expect(
        [for (final item in withMode(swapped, PaneMode.flow).items) item.id],
        ['d', 'c'],
      );
    });

    test('fewer columns narrow and move what no longer fits', () {
      final narrowed = withColumns(layout.home.root, 2);
      final inner = narrowed.items.last;
      expect((inner.w, inner.x), (2, 0));
      expect(narrowed.columns, 2);
    });
  });

  test('deleting a folder takes its entities and what was in it', () {
    final layout = Layout(
      inbox: 'p',
      panels: [
        Panel(
          id: Layout.homeId,
          root: Pane(
            id: 'p',
            items: [
              entity('a'),
              LayoutItem.of('f', id: 'opens', prefab: folderPrefabId),
            ],
          ),
        ),
        Panel(
          id: 'f',
          root: Pane(
            id: 'f/root',
            items: [
              entity('b'),
              const LayoutItem(
                id: 'a2',
                kind: ItemKind.prefab,
                ref: cardPrefabId,
                vars: {'source': Variable('app:a')},
              ),
            ],
          ),
        ),
      ],
    );
    final deleted = removePanel(layout, 'f');
    expect(deleted.panel('f'), isNull);
    expect(ids(deleted, 'p'), ['a']);
    // Only what is now nowhere counts as removed.
    expect(deleted.removed, {'app:b'});
    expect(removePanel(layout, 'nothing'), same(layout));
  });

  test('counts how often each entity is on the TV', () {
    final layout = home(
      Pane(
        id: 'p',
        items: [
          entity('a'),
          const LayoutItem(
            id: 'again',
            kind: ItemKind.prefab,
            ref: cardPrefabId,
            vars: {'source': Variable('app:a')},
          ),
          const LayoutItem(id: 'w', kind: ItemKind.component, ref: 'clock'),
        ],
      ),
    );
    expect(placedCounts(layout), {'app:a': 2});
  });

  group('sidebars from the catalogue', () {
    test('an edge is free with no sidebar, or with an empty one', () {
      final layout = withBar(Layout.fromJson(const {}).normalised(), 'top');
      final full = changePanel(
        withBar(layout, 'left'),
        'left',
        (panel) => panel.withRoot(
          panel.root.copyWith(
            items: const [
              LayoutItem(
                id: 'a',
                kind: ItemKind.prefab,
                ref: cardPrefabId,
                vars: {'source': Variable('x')},
              ),
            ],
          ),
        ),
      );
      expect(freeEdges(layout), Layout.barIds);
      expect(freeEdges(full), ['right', 'top', 'bottom']);
    });

    test('only an edge within reach takes it, the nearest free one', () {
      const all = Layout.barIds;
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
