import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/modules/cells_layout.dart';
import 'package:openlauncher/features/modules/free_layout.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';
import 'package:openlauncher/features/modules/variables_drawer.dart';

/// Wraps every pane's grid. Unused on the TV; the editor uses it to locate
/// panes.
class PaneFrame extends InheritedWidget {
  const PaneFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Node pane, Widget grid) wrap;

  @override
  bool updateShouldNotify(PaneFrame oldWidget) => wrap != oldWidget.wrap;
}

/// Lays a pane's children out on its cells, or by their transforms when it
/// has no Layout. Its children read its variables and inherit its style.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.pane, required this.tile});

  final Node pane;
  final Widget Function(Node child) tile;

  @override
  Widget build(BuildContext context) {
    final pane = this.pane;
    final grid = pane.mode == PaneMode.free
        ? FreeLayout(node: pane, tile: tile)
        : CellsLayout(pane: pane, tile: tile);
    final scoped = pane.vars.isEmpty
        ? grid
        : Consumer(
            builder: (context, ref, child) => TemplateScope(
              values: scopeOf(
                ref.watch,
                pane.id,
                pane.vars,
                TemplateScope.of(context),
              ).inner,
              child: child!,
            ),
            child: grid,
          );
    return StyleScope.under(context, pane.style, scoped);
  }
}

/// The corners of [node]'s box.
BorderRadius shapeOf(Node node) => styleShape(node.box, defaultCorner);
