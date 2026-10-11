import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/after_frame.dart';
import 'package:openlauncher/editor/layers.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/features/home/component_view.dart';
import 'package:openlauncher/features/home/focus_tile.dart';

/// Where the focus goes from one place when the D-pad is pressed one way.
@immutable
class _Move {
  const _Move(this.layer, this.from, this.to, this.item);

  final EditLayer layer;
  final Rect from, to;

  /// The layout item it starts on, if it starts on one.
  final String? item;

  @override
  bool operator ==(Object other) =>
      other is _Move &&
      other.layer == layer &&
      other.from == from &&
      other.to == to &&
      other.item == item;

  @override
  int get hashCode => Object.hash(layer, from, to, item);
}

/// Draws the layers that are switched on over the launcher's screen, which
/// it is laid over and is the size of. It takes no part in what happens on
/// the screen: nothing in it can be touched.
class LayerStack extends ConsumerStatefulWidget {
  const LayerStack({super.key, required this.navigator});

  /// The launcher's navigator, whose screen this is over.
  final GlobalKey<NavigatorState> navigator;

  @override
  ConsumerState<LayerStack> createState() => _LayerStackState();
}

class _LayerStackState extends ConsumerState<LayerStack> {
  /// Every move the D-pad can make on the screen as it is now, found the
  /// way the launcher finds it: from what can take the focus on the screen
  /// in front, by the launcher's own rule.
  List<_Move> _find() {
    final screen = context.findRenderObject();
    // The screen in front: the home screen, or the popup last opened over
    // it. Each has its own focus scope, under the navigator's.
    final scope = widget.navigator.currentState?.focusNode.children
        .whereType<FocusScopeNode>()
        .lastOrNull;
    if (screen is! RenderBox || scope == null) return const [];
    final spots = <NavSpot<FocusNode>>[];
    for (final node in scope.traversalDescendants) {
      final context = node.context;
      if (node is FocusScopeNode || !node.canRequestFocus || context == null) {
        continue;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      spots.add(
        NavSpot(
          node,
          // Measured on the launcher's screen, however large it is shown.
          MatrixUtils.transformRect(
            box.getTransformTo(screen),
            Offset.zero & box.size,
          ),
          PaneScope.peek(context),
        ),
      );
    }
    return [
      for (final layer in ref.read(layersProvider))
        if (layer.direction case final direction?)
          for (final spot in spots)
            if (navigate(spot, spots, direction) case final target?)
              _Move(
                layer,
                spot.rect,
                target.rect,
                spot.id.context
                    ?.findAncestorWidgetOfExactType<ComponentView>()
                    ?.component
                    .id,
              ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final layers = ref.watch(layersProvider);
    final selected = ref.watch(selectionProvider);
    if (layers.isEmpty) return const SizedBox.shrink();
    // Where things are changes with scrolling, popups, rails and the
    // layout, none of which say so: looked at again after every frame.
    return AfterFrame<List<_Move>>(
      read: _find,
      same: listEquals,
      builder: (context, moves) => IgnorePointer(
        child: CustomPaint(
          painter: _MovesPainter([
            for (final move in moves ?? const <_Move>[])
              // With things picked out, only where the focus goes from them.
              if (layers.contains(move.layer) &&
                  (selected.isEmpty || selected.contains(move.item)))
                move,
          ]),
        ),
      ),
    );
  }
}

/// An arrow for each move, from the edge the focus leaves by to the edge
/// it arrives at.
class _MovesPainter extends CustomPainter {
  const _MovesPainter(this.moves);

  final List<_Move> moves;

  static const _head = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final move in moves) {
      final a = move.from, c = move.to;
      final direction = move.layer.direction!;
      final sideways =
          direction == NavDirection.left || direction == NavDirection.right;
      final forwards =
          direction == NavDirection.right || direction == NavDirection.down;
      // Kept a little off the middle, so that there and back do not overlap.
      final shift = forwards ? 5.0 : -5.0;
      var start = sideways
          ? Offset(forwards ? a.right : a.left, a.center.dy + shift)
          : Offset(a.center.dx + shift, forwards ? a.bottom : a.top);
      var end = sideways
          ? Offset(forwards ? c.left : c.right, c.center.dy + shift)
          : Offset(c.center.dx + shift, forwards ? c.top : c.bottom);
      // Where the two overlap, or it would have to turn back: from middle
      // to middle.
      final travel = sideways ? end.dx - start.dx : end.dy - start.dy;
      if (travel * (forwards ? 1 : -1) < 4) {
        final aside = sideways ? Offset(0, shift) : Offset(shift, 0);
        start = a.center + aside;
        end = c.center + aside;
      }
      final along = end - start;
      if (along.distance < 1) continue;
      final angle = along.direction;
      Offset back(double turn) =>
          end - Offset(cos(angle + turn), sin(angle + turn)) * _head;
      final arrow = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy)
        ..moveTo(back(0.45).dx, back(0.45).dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(back(-0.45).dx, back(-0.45).dy);
      Paint stroke(Color colour, double width) => Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      // A dark edge, to stand out on any wallpaper.
      canvas.drawPath(arrow, stroke(const Color(0xB3000000), 4));
      canvas.drawPath(arrow, stroke(move.layer.colour, 2));
    }
  }

  @override
  bool shouldRepaint(_MovesPainter oldDelegate) =>
      !listEquals(moves, oldDelegate.moves);
}
