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

/// Whether [node] is a panel: it draws nothing itself and arranges its
/// children on cells or by transform. A panel is padded and rounded more,
/// what is in it is cut off at its box, and its name is its heading.
bool isPanel(Node node) => node.isPane && !node.mode.inLine;

/// What [node]'s box takes where its style sets nothing.
BoxDefaults boxDefaultsOf(Node node) => isPanel(node)
    ? const BoxDefaults(
        padding: LayoutModule.defaultPadding,
        corner: LayoutModule.defaultCorner,
        padsBare: true,
        clips: true,
      )
    : const BoxDefaults();

/// The corners of [pane]'s box.
BorderRadius shapeOf(Node pane) =>
    styleShape(pane.box, boxDefaultsOf(pane).corner);

/// Padding between a panel's heading and what is in it.
const underHeading = 10.0;

/// A panel's heading.
class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: Colors.white70),
  );
}
