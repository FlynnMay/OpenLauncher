import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/layout/layout_enums.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:test/test.dart';

Node card(String id, {double? x, double? y}) =>
    Node.of('app:$id', id: id, prefab: 'card', variable: 'what', x: x, y: y);

Layout home(Node root, {Set<String> removed = const {}}) => Layout(
  inbox: root.id,
  removed: removed,
  screens: [Screen(id: 'home', root: root)],
);

List<String> idsIn(Layout layout, String container) => [
  for (final child in layout.node(container)!.children) child.id,
];

/// Applies [command], then its inverse on the result, and checks the layout is
/// as it was; then the redo, and checks that is as it was after.
Layout roundTrip(Layout before, LayoutCommand command) {
  final after = command.apply(before);
  final undo = command.inverse(before);
  final back = undo.apply(after);
  expect(back.toJson(), before.toJson());

  final redo = undo.inverse(after);
  expect(redo.apply(back).toJson(), after.toJson());
  return after;
}

void main() {
  patchRules();
  final flow = home(
    Node.layout(
      id: 'p',
      children: [
        card('a'),
        card('b'),
        Node.layout(id: 'inner', children: [card('c'), card('d')]),
      ],
    ),
  );

  group('RemoveNodes', () {
    test('takes nodes out and an undo puts them back where they were', () {
      final after = roundTrip(flow, const RemoveNodes(['b']));
      expect(idsIn(after, 'p'), ['a', 'inner']);
    });

    test('a container goes with what it holds, and comes back with it', () {
      final after = roundTrip(flow, const RemoveNodes(['inner']));
      expect(after.node('c'), isNull);
    });

    test('one command for a selection, one undo for all of it', () {
      final after = roundTrip(flow, const RemoveNodes(['a', 'c', 'inner']));
      expect(idsIn(after, 'p'), ['b']);
    });

    test('marks entities nothing else places as removed, and undoes it', () {
      final after = roundTrip(flow, const RemoveNodes(['a']));
      expect(after.removed, {'app:a'});
    });

    test('refuses to remove what is not there', () {
      expect(
        () => const RemoveNodes(['nope']).apply(flow),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('DropNode', () {
    test('adds a node, and an undo takes it off', () {
      final after = roundTrip(
        flow,
        DropNode(card('n'), const Drop('p', before: 'b')),
      );
      expect(idsIn(after, 'p'), ['a', 'n', 'b', 'inner']);
    });

    test('moves a node between containers, and an undo puts it back', () {
      final after = roundTrip(flow, DropNode(card('a'), const Drop('inner')));
      expect(idsIn(after, 'inner'), ['c', 'd', 'a']);
      expect(idsIn(after, 'p'), ['b', 'inner']);
    });

    test('puts back the cells of what a grid pushed aside', () {
      final grid = home(
        Node.layout(
          id: 'g',
          mode: LayoutMode.grid,
          columns: 4,
          children: [card('a', x: 1, y: 0), card('b', x: 2, y: 0)],
        ),
      );
      roundTrip(grid, DropNode(card('n'), const Drop('g', x: 1, y: 0)));
    });

    test('a docked container it opens goes with the undo', () {
      final opens = Node.layout(id: 'menu', children: [card('m')]);
      final after = roundTrip(
        flow,
        DropNode(card('n'), const Drop('p'), opens: opens),
      );
      expect(after.node('menu'), isNotNull);
    });

    test('refuses a drop into a layout that is gone, or into itself', () {
      expect(
        () => DropNode(card('n'), const Drop('nope')).apply(flow),
        throwsA(isA<CommandRefused>()),
      );
      final inner = flow.node('inner')!;
      expect(
        () => DropNode(inner, const Drop('inner')).apply(flow),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('an undo leaves what another editor did inside a container', () {
      final command = DropNode(card('n'), const Drop('p', before: 'b'));
      final undo = command.inverse(flow);
      // Someone adds a card to the inner container meanwhile.
      final meanwhile = command
          .apply(flow)
          .withContainer(
            'inner',
            (inner) => inner.copyWith(children: [...inner.children, card('z')]),
          );
      final back = undo.apply(meanwhile);
      expect(idsIn(back, 'p'), ['a', 'b', 'inner']);
      expect(idsIn(back, 'inner'), ['c', 'd', 'z']);
    });

    test('an undo refuses when the container it restores has gone', () {
      final command = DropNode(card('n'), const Drop('inner'));
      final undo = command.inverse(flow);
      final without = RemoveNodes(['inner']).apply(command.apply(flow));
      expect(() => undo.apply(without), throwsA(isA<CommandRefused>()));
    });
  });

  group('PatchLayout', () {
    Layout widened(Layout layout) => layout.withContainer(
      'p',
      (p) => p.copyWith(
        children: [
          for (final child in p.children)
            child.id == 'a' ? child.sized(2, 1) : child,
        ],
      ),
    );

    test('turns one layout into another, and back again', () {
      final patch = PatchLayout.turning(flow, widened(flow));
      expect(patch.containers.keys, ['p']);
      expect(patch.apply(flow).toJson(), widened(flow).toJson());
      roundTrip(flow, patch);
    });

    test('is empty when nothing changed, and says so', () {
      final patch = PatchLayout.turning(flow, flow);
      expect(patch.isEmpty, isTrue);
      expect(patch.apply(flow).toJson(), flow.toJson());
    });

    test('carries what a screen root changed, and undoes it', () {
      final renamed = flow.withContainer(
        'p',
        (root) => root.copyWith(name: 'Home'),
      );
      final patch = PatchLayout.turning(flow, renamed);
      expect(patch.roots.keys, ['home']);
      expect(patch.containers, isEmpty);
      roundTrip(flow, patch);
    });

    test('leaves containers it did not change as another editor left them', () {
      final patch = PatchLayout.turning(flow, widened(flow));
      final meanwhile = flow.withContainer(
        'inner',
        (inner) => inner.copyWith(children: [...inner.children, card('z')]),
      );
      final after = patch.apply(meanwhile);
      expect(idsIn(after, 'inner'), ['c', 'd', 'z']);
      expect(after.node('p')!.children.first.id, 'a');
    });

    test('moves a node between containers and keeps what it holds', () {
      final moved = DropNode(
        flow.node('inner')!,
        const Drop('p', before: 'a'),
      ).apply(flow);
      final patch = PatchLayout.turning(flow, moved);
      expect(patch.apply(flow).toJson(), moved.toJson());
      roundTrip(flow, patch);
    });

    test('refuses a container that is gone', () {
      final reordered = flow.withContainer(
        'inner',
        (inner) => inner.copyWith(children: inner.children.reversed.toList()),
      );
      final patch = PatchLayout.turning(flow, reordered);
      expect(patch.containers.keys, ['inner']);
      final without = const RemoveNodes(['inner']).apply(flow);
      expect(() => patch.apply(without), throwsA(isA<CommandRefused>()));
    });
  });

  group('commandFromJson', () {
    test('reads what toJson writes, for every node command', () {
      final after = const RemoveNodes(['a']).apply(flow);
      for (final command in <Command>[
        const RemoveNodes(['a', 'b']),
        DropNode(
          card('n'),
          const Drop('p', before: 'b', x: 1, y: 2),
          opens: Node.layout(id: 'menu'),
        ),
        DropNode(
          card('n'),
          const Drop(
            'p',
            rect: Box.fromLTWH(1, 2, 3, 4),
            size: Extent(800, 400),
          ),
        ),
        const RemoveNodes(['a']).inverse(flow),
        PatchLayout(removed: after.removed),
      ]) {
        expect(commandFromJson(command.toJson()).toJson(), command.toJson());
      }
    });

    test('a command sent as JSON does the same as the one built here', () {
      final sent = (commandFromJson(
        const RemoveNodes(['b']).toJson(),
      ) as LayoutCommand).apply(flow);
      expect(sent.toJson(), const RemoveNodes(['b']).apply(flow).toJson());
    });

    test('refuses what is missing', () {
      expect(
        () => commandFromJson({'type': 'node.remove'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => commandFromJson({'type': 'node.drop', 'drop': {}}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

void patchRules() {
  group('PatchLayout rules', () {
    final flow = home(
      Node.layout(
        id: 'p',
        children: [
          card('a'),
          Node.layout(id: 'inner', children: [card('c')]),
        ],
      ),
    );

    test('refuses a node that would be on two nodes', () {
      final patch = PatchLayout(
        containers: {
          'inner': [card('c'), card('a')],
        },
      );
      expect(() => patch.apply(flow), throwsA(isA<CommandRefused>()));
    });

    test('allows a node moved from one container to another', () {
      final moved = PatchLayout(
        containers: {
          'p': [Node.layout(id: 'inner', children: const [])],
          'inner': [card('c'), card('a')],
        },
      );
      expect(idsIn(moved.apply(flow), 'inner'), ['c', 'a']);
    });

    test('refuses a container that would nest too deep', () {
      Node deep(int levels) => levels == 0
          ? card('leaf')
          : Node.layout(id: 'l$levels', children: [deep(levels - 1)]);
      final patch = PatchLayout(
        containers: {
          'inner': [deep(Node.maxDepth)],
        },
      );
      expect(() => patch.apply(flow), throwsA(isA<CommandRefused>()));
    });

    test('lets an edit through that only touches what was already there', () {
      final patch = PatchLayout(
        containers: {
          'p': [card('a').sized(2, 1), flow.node('inner')!],
        },
      );
      expect(() => patch.apply(flow), returnsNormally);
    });
  });
}
