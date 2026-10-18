import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/stage/stage.dart';

void main() {
  test('cells go by whole cells; without a layout, pixels, a few at a time '
      'while snapping', () {
    final free = Node.layout(id: 'p', mode: LayoutMode.free);
    final grid = Node.layout(id: 'p', mode: LayoutMode.grid);
    expect(stepIn(free, snap: true), freeStep);
    expect(stepIn(free, snap: false), 1);
    expect(stepIn(free, snap: true, step: 20), 20);
    expect(stepIn(grid, snap: true), 1);
    expect(stepIn(grid, snap: false), 1);
    expect(stepIn(Node.layout(id: 'p'), snap: false), 1);
  });

  test('values go to the nearest step, without stray digits', () {
    expect(snapTo(2.4, 1), 2);
    expect(snapTo(2.5, 1), 3);
    expect(snapTo(13, freeStep), 16);
    expect(snapTo(11.9, freeStep), 8);
    // A fraction of a step comes out clean.
    expect(snapTo(0.1499999, 0.05), 0.15);
    expect(snapTo(-0.02, 0.05), 0);
  });
}
