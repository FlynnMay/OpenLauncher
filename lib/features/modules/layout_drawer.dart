import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/modules/cells_layout.dart';
import 'package:openlauncher/features/modules/free_layout.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';
import 'package:openlauncher/features/modules/variables_drawer.dart';

/// Wraps every container's grid. Unused on the TV; the editor uses it to locate
/// containers.
class LayoutFrame extends InheritedWidget {
  const LayoutFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Node container, Widget grid) wrap;

  @override
  bool updateShouldNotify(LayoutFrame oldWidget) => wrap != oldWidget.wrap;
}

/// Lays a container's children out on its cells, or by their transforms when it
/// has no Layout. Its children read its variables and inherit its style.
class ChildrenLayout extends StatelessWidget {
  const ChildrenLayout({
    super.key,
    required this.container,
    required this.tile,
  });

  final Node container;
  final Widget Function(Node child) tile;

  @override
  Widget build(BuildContext context) {
    final container = this.container;
    final grid = container.mode == LayoutMode.free
        ? FreeLayout(node: container, tile: tile)
        : CellsLayout(container: container, tile: tile);
    final scoped = container.vars.isEmpty
        ? grid
        : Consumer(
            builder: (context, ref, child) => TemplateScope(
              values: scopeOf(
                ref.watch,
                container.id,
                container.vars,
                TemplateScope.of(context),
              ).inner,
              child: child!,
            ),
            child: grid,
          );
    return StyleScope.under(context, container.style, scoped);
  }
}

/// The corners of [node]'s box.
BorderRadius shapeOf(Node node) => styleShape(node.box, defaultCorner);
