import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/layout_edit.dart';

LayoutItem card(
  String id, {
  double w = 1,
  double h = 1,
  double? x,
  double? y,
}) => LayoutItem(
  id: id,
  kind: ItemKind.card,
  ref: 'app:$id',
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
  test('new ids start as asked and do not repeat', () {
    final made = {for (var i = 0; i < 200; i++) newId('i')};
    expect(made, hasLength(200));
    expect(made.every((id) => id.startsWith('i') && id.length == 8), isTrue);
  });

  group('settle', () {
    test('the fixed item gets its cell and what was there moves aside', () {
      final settled = settle(
        [card('a', x: 0, y: 0), card('b', x: 1, y: 0), card('new', x: 0, y: 0)],
        3,
        fixed: 'new',
      );
      expect((settled[2].x, settled[2].y), (0, 0));
      expect((settled[1].x, settled[1].y), (1, 0));
      // The nearest free cell to where it was.
      expect((settled[0].x, settled[0].y), (0, 1));
    });

    test('an item with no wish takes the first free cell', () {
      final settled = settle([card('a', x: 0, y: 0), card('b')], 2);
      expect((settled[1].x, settled[1].y), (1, 0));
    });

    test('nothing is wider than the pane or left overlapping', () {
      final settled = settle(
        [card('a', w: 5, x: 3, y: 0), card('b', w: 2, h: 2, x: 0, y: 0)],
        3,
        fixed: 'a',
      );
      expect((settled[0].w, settled[0].x, settled[0].y), (3, 0, 0));
      expect(settled[1].y, 1);
    });
  });

  group('dropItem', () {
    final flow = home(Pane(id: 'p', items: [card('a'), card('b'), card('c')]));

    test('goes in front of an item of a pane that flows, or to its end', () {
      expect(
        ids(dropItem(flow, card('n'), const Drop('p', before: 'b')), 'p'),
        ['a', 'n', 'b', 'c'],
      );
      expect(ids(dropItem(flow, card('n'), const Drop('p')), 'p'), [
        'a',
        'b',
        'c',
        'n',
      ]);
    });

    test('moves an item that is already there instead of adding it', () {
      final moved = dropItem(flow, card('c'), const Drop('p', before: 'a'));
      expect(ids(moved, 'p'), ['c', 'a', 'b']);
    });

    test('takes the asked cell of a grid and pushes aside what was there', () {
      final grid = home(
        Pane(
          id: 'p',
          mode: PaneMode.grid,
          columns: 4,
          items: [card('a', x: 1, y: 0)],
        ),
      );
      final dropped = dropItem(grid, card('n'), const Drop('p', x: 1, y: 0));
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
          items: [card('a', x: 0, y: 0)],
        ),
      );
      final dropped = dropItem(
        free,
        card('n', w: 2),
        const Drop('p', x: 3, y: 0),
      );
      expect(at(dropped, 'n'), (2, 0));
      // With nowhere asked for, under what is there.
      expect(at(dropItem(free, card('m'), const Drop('p')), 'm'), (0, 1));
    });

    test('moves an item from one pane into another inside it', () {
      final nested = home(
        Pane(
          id: 'p',
          items: [
            card('a'),
            LayoutItem.pane(const Pane(id: 'inner'), w: 3, h: 2),
          ],
        ),
      );
      final moved = dropItem(nested, card('a'), const Drop('inner'));
      expect(ids(moved, 'p'), ['pane:inner']);
      expect(ids(moved, 'inner'), ['a']);
    });

    test('a card that is placed is no longer removed', () {
      final layout = home(const Pane(id: 'p'), removed: {'app:n', 'app:z'});
      expect(dropItem(layout, card('n'), const Drop('p')).removed, {'app:z'});
    });

    test('a new folder brings its popup with it', () {
      final folder = Panel(
        id: 'f',
        title: 'Games',
        root: const Pane(id: 'f/root'),
      );
      final dropped = dropItem(
        flow,
        const LayoutItem(id: 'i', kind: ItemKind.panel, ref: 'f'),
        const Drop('p'),
        panel: folder,
      );
      expect(dropped.panel('f')?.title, 'Games');
      // The TV keeps the card because the popup it opens exists.
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
      expect(refusal(layout, card('a'), 'p+++'), isNull);
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

    test('a sidebar takes no panes', () {
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
        contains('sidebar'),
      );
    });
  });

  group('removeItem', () {
    test('notes a card as removed once it is nowhere', () {
      final layout = home(
        Pane(
          id: 'p',
          items: [
            card('a'),
            const LayoutItem(id: 'again', kind: ItemKind.card, ref: 'app:a'),
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
            card('a'),
            LayoutItem.pane(Pane(id: 'inner', items: [card('b'), card('c')])),
          ],
        ),
      );
      final removed = removeItem(layout, 'pane:inner');
      expect(ids(removed, 'p'), ['a']);
      expect(removed.removed, {'app:b', 'app:c'});
    });
  });

  test('counts how often each card is on the TV', () {
    final layout = home(
      Pane(
        id: 'p',
        items: [
          card('a'),
          const LayoutItem(id: 'again', kind: ItemKind.card, ref: 'app:a'),
          const LayoutItem(id: 'w', kind: ItemKind.widget, ref: 'clock'),
        ],
      ),
    );
    expect(placedCounts(layout), {'app:a': 2});
  });
}
