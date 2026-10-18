import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/layout_drawer.dart';

/// [node]'s children where their transforms put them, as for a node with no
/// Layout. Without a height to anchor to it is as tall as what is in it.
class FreeLayout extends StatelessWidget {
  const FreeLayout({super.key, required this.node, required this.tile});

  final Node node;
  final Widget Function(Node child) tile;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    final frame = context.dependOnInheritedWidgetOfExactType<LayoutFrame>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : node.children.fold(
                0.0,
                (tallest, child) =>
                    max(tallest, child.transform.rectIn(Size(width, 0)).bottom),
              );
        final size = Size(width, height);
        final placed = SizedBox.fromSize(
          size: size,
          child: ContainerScope(
            containers: [...ContainerScope.of(context), node.id],
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final child in node.shown)
                  if (!child.hidden && !child.offCells)
                    Positioned.fromRect(
                      key: ValueKey(child.id),
                      rect: child.transform.rectIn(size),
                      child: tile(child),
                    ),
              ],
            ),
          ),
        );
        return frame == null ? placed : frame.wrap(node, placed);
      },
    );
  }
}
