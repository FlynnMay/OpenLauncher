import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// An entity one cell big at column [x], row [y], in [containers].
NavSpot<String> _at(
  String id,
  double x,
  double y, [
  List<String> containers = const ['g'],
]) => NavSpot(id, Rect.fromLTWH(x * 100, y * 100, 80, 60), containers);

String? _go(String from, NavDirection direction, List<NavSpot<String>> spots) =>
    navigate(spots.firstWhere((s) => s.id == from), spots, direction)?.id;

void main() {
  test('kinship of containers', () {
    expect(navKinship(['g', 'a'], ['g', 'a']), NavKinship.same);
    expect(navKinship(['g', 'a'], ['g', 'a', 'x']), NavKinship.child);
    expect(navKinship(['g', 'a'], ['g']), NavKinship.parent);
    expect(navKinship(['g', 'a'], ['g', 'b']), NavKinship.other);
    expect(navKinship(['g', 'a'], ['g', 'b', 'x']), NavKinship.other);
    // A button that is in no pane, and a rail, are neither kin.
    expect(navKinship(['g'], []), NavKinship.other);
    expect(navKinship(['g'], ['left']), NavKinship.other);
  });

  group('within one pane', () {
    final grid = [
      _at('a', 0, 0),
      _at('b', 1, 0),
      _at('c', 2, 0),
      _at('d', 0, 1),
      _at('e', 1, 1),
    ];

    test('goes to the neighbour in line', () {
      expect(_go('a', NavDirection.right, grid), 'b');
      expect(_go('c', NavDirection.left, grid), 'b');
      expect(_go('b', NavDirection.down, grid), 'e');
      expect(_go('e', NavDirection.up, grid), 'b');
    });

    test('goes nowhere when nothing lies that way', () {
      expect(_go('a', NavDirection.left, grid), isNull);
      expect(_go('a', NavDirection.up, grid), isNull);
      expect(_go('d', NavDirection.down, grid), isNull);
    });

    test('takes the nearest when nothing is in line', () {
      // Nothing is below c; e is the closest thing lower down.
      expect(_go('c', NavDirection.down, grid), 'e');
      // Right of e there is only c, a row up.
      expect(_go('e', NavDirection.right, grid), 'c');
    });

    test('prefers what is in line over what is merely close', () {
      final spots = [_at('a', 0, 0), _at('far', 4, 0), _at('near', 1, 1)];
      expect(_go('a', NavDirection.right, spots), 'far');
    });
  });

  group('between containers', () {
    // A pane p on the global pane g, with a pane q inside it and a pane s
    // beside it. Everything is on one row, left to right:
    //   loose0  [p: p0  [q: q0]  p1]  [s: s0]  loose1
    final spots = [
      _at('loose0', 0, 0),
      _at('p0', 1, 0, ['g', 'p']),
      _at('q0', 2, 0, ['g', 'p', 'q']),
      _at('p1', 3, 0, ['g', 'p']),
      _at('s0', 4, 0, ['g', 's']),
      _at('loose1', 5, 0),
    ];

    test('the same pane comes first, even past something nearer', () {
      // q0 is next to p0, but p1 is in p0's own pane.
      expect(_go('p0', NavDirection.right, spots), 'p1');
      expect(_go('p1', NavDirection.left, spots), 'p0');
    });

    test('then a pane inside, then the pane around, then any other', () {
      final noP1 = spots.where((s) => s.id != 'p1').toList();
      // With nothing else of its own pane that way: the child pane.
      expect(_go('p0', NavDirection.right, noP1), 'q0');
      // From the last entity of p: the pane around it, past the sibling s.
      expect(_go('p1', NavDirection.right, spots), 'loose1');
      // And only with nothing there either, the sibling.
      final noLoose = spots.where((s) => s.id != 'loose1').toList();
      expect(_go('p1', NavDirection.right, noLoose), 's0');
    });

    test('from the global pane, containers on it are entered at their nearest entity', () {
      // Its own pane first: the other loose entity, however far.
      expect(_go('loose0', NavDirection.right, spots), 'loose1');
      final alone = spots.where((s) => s.id != 'loose1').toList();
      expect(_go('loose0', NavDirection.right, alone), 'p0');
    });

    test('leaving a pane, straight ahead beats the pane around off to the side', () {
      // A row of entities in pane b, a pane a directly above it, and one entity
      // of the global pane far up in the corner.
      final stacked = [
        _at('corner', 0, 0),
        _at('a0', 3, 1, ['g', 'a']),
        _at('b0', 3, 2, ['g', 'b']),
        _at('b1', 4, 2, ['g', 'b']),
      ];
      expect(_go('b0', NavDirection.up, stacked), 'a0');
      // With nothing straight ahead, the pane around comes before a sibling.
      final askew = [
        _at('corner', 0, 0),
        _at('a0', 6, 1, ['g', 'a']),
        _at('b0', 3, 2, ['g', 'b']),
      ];
      expect(_go('b0', NavDirection.up, askew), 'corner');
    });

    test('from an inner pane, out to the pane around it', () {
      expect(_go('q0', NavDirection.right, spots), 'p1');
      expect(_go('q0', NavDirection.left, spots), 'p0');
    });
  });
}
