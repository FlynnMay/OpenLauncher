import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/resize_handles.dart';

void main() {
  testWidgets('reports how far a handle is dragged, then that it was let go', (
    tester,
  ) async {
    final dragged = <(ResizeHandle, Offset)>[];
    final done = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ResizeHandles(
              rect: const Rect.fromLTWH(100, 100, 200, 100),
              onDragged: (handle, moved) => dragged.add((handle, moved)),
              onDone: ({required kept}) => done.add(kept),
            ),
          ],
        ),
      ),
    );
    // One at each corner and the middle of each side.
    expect(find.byType(GestureDetector), findsNWidgets(8));

    // The handle in the middle of the right-hand side.
    final gesture = await tester.startGesture(const Offset(300, 150));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(25, 5));
    await gesture.up();
    expect(dragged.last.$1, ResizeHandle.right);
    // What is reported is the whole way since it was taken hold of.
    expect(dragged.last.$2.dx, greaterThan(40));
    expect(done, [true]);
  });

  testWidgets('offers only the handles asked for', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ResizeHandles(
              rect: const Rect.fromLTWH(100, 100, 200, 100),
              handles: const {ResizeHandle.right, ResizeHandle.bottom},
              onDragged: (_, _) {},
              onDone: ({required kept}) {},
            ),
          ],
        ),
      ),
    );
    expect(find.byType(GestureDetector), findsNWidgets(2));
  });
}
