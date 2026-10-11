import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/snapping.dart';

void main() {
  test(
    'only an "Anywhere" pane with snapping off goes by less than a cell',
    () {
      final free = Component.pane(id: 'p', mode: PaneMode.free);
      final grid = Component.pane(id: 'p', mode: PaneMode.grid);
      expect(stepIn(free, snap: true), 1);
      expect(stepIn(free, snap: false), freeStep);
      expect(stepIn(grid, snap: false), 1);
      expect(stepIn(Component.pane(id: 'p'), snap: false), 1);
    },
  );

  test('values go to the nearest step, without stray digits', () {
    expect(snapTo(2.4, 1), 2);
    expect(snapTo(2.5, 1), 3);
    expect(snapTo(1.234, freeStep), 1.25);
    expect(snapTo(0.3, freeStep), 0.3);
    // 0.15 is not exactly a multiple of 0.05 in binary; it must come out so.
    expect(snapTo(0.1499999, freeStep), 0.15);
    expect(snapTo(-0.02, freeStep), 0);
  });
}
