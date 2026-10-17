import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/stage/tv_screen.dart';
import 'package:openlauncher/features/home/docked_node.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';

/// The open prefab alone on the TV's screen: its root at its default size,
/// enlarged to fill the screen. A docked one is shown open where it docks.
class PrefabScreen extends ConsumerWidget {
  const PrefabScreen({super.key});

  /// Left clear around it.
  static const _margin = 60.0;

  static const _mostScale = 3.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final container = ref.watch(editedLayoutProvider)?.home.root;
    final root = container?.children.firstOrNull;
    if (container == null || root == null) {
      return SizedBox.fromSize(size: TvScreen.size);
    }
    if (root.isDocked) {
      return SizedBox.fromSize(
        size: TvScreen.size,
        child: Material(
          color: const Color(0xFF14151A),
          child: TileTraversal(
            child: DockHold(
              ids: {root.id},
              child: DockedNode(container: root),
            ),
          ),
        ),
      );
    }
    final width =
        container.columns * prefabCellWidth +
        (container.columns - 1) * container.spacingX;
    final metrics = CellMetrics(container, width);
    final w = metrics.across(root.w), h = metrics.down(root.h);
    final Size(width: across, height: down) = TvScreen.size;
    final scale = min(
      _mostScale,
      min((across - 2 * _margin) / w, (down - 2 * _margin) / h),
    );
    return SizedBox.fromSize(
      size: TvScreen.size,
      child: Material(
        color: const Color(0xFF14151A),
        child: TileTraversal(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: (across - w * scale) / 2,
                top: (down - h * scale) / 2,
                width: width,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: ChildrenLayout(
                    container: container,
                    tile: (component) => NodeView(component: component),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
