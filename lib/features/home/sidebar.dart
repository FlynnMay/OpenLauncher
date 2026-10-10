import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// Keeps the sidebars named open whatever has the focus, and shown even
/// with nothing in them. The TV has none; the editor uses it for a sidebar
/// that is being arranged.
class SidebarHold extends InheritedWidget {
  const SidebarHold({super.key, required this.ids, required super.child});

  /// The panel ids of the sidebars held open.
  final Set<String> ids;

  @override
  bool updateShouldNotify(SidebarHold oldWidget) =>
      !ids.containsAll(oldWidget.ids) || !oldWidget.ids.containsAll(ids);
}

/// A pane along one edge of the screen that opens over the home screen
/// while the focus is in it, and otherwise keeps to a strip along its edge,
/// or out of sight. Inside it is a pane like any other.
///
/// It is always laid out at its open size, whatever of it shows, so nothing
/// in it moves about as it opens.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.view});

  final PanelView view;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _box = GlobalKey();
  bool _focused = false;

  /// What of the sidebar can be seen, on the display.
  Rect? _visible() => switch (_box.currentContext?.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final panel = widget.view.panel;
    final held =
        context.dependOnInheritedWidgetOfExactType<SidebarHold>()?.ids.contains(
          panel.id,
        ) ??
        false;
    // With nothing in it there is nothing to show or to go to.
    if (widget.view.isEmpty && !held) return const SizedBox.shrink();
    final open = _focused || held;
    final edge = panel.edge!;
    final alignment = switch (edge) {
      BarEdge.left => Alignment.centerLeft,
      BarEdge.right => Alignment.centerRight,
      BarEdge.top => Alignment.topCenter,
      BarEdge.bottom => Alignment.bottomCenter,
    };
    final root = widget.view.root;
    final scrim = Colors.black.withValues(alpha: open ? 0.94 : 0);
    return LayoutBuilder(
      builder: (context, screen) {
        // As big as it is set to be, and no bigger than the screen.
        final width = panel.openWidth.clamp(0.0, screen.maxWidth);
        final height = panel.openHeight.clamp(0.0, screen.maxHeight);
        final across = panel.opensAcross;
        final shown = open
            ? (across ? width : height)
            : panel.closedSize.clamp(0.0, across ? width : height);
        return Align(
          alignment: alignment,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (inside) => setState(() => _focused = inside),
            child: AnimatedContainer(
              key: _box,
              duration: FocusTile.duration,
              curve: Curves.easeOut,
              width: across ? shown : width,
              height: across ? height : shown,
              clipBehavior: Clip.hardEdge,
              // Fades into the home screen on the side it opens towards,
              // unless the pane has a background of its own.
              decoration: BoxDecoration(
                gradient: root.pane.style.isEmpty
                    ? LinearGradient(
                        begin: alignment,
                        end: -alignment,
                        colors: [scrim, scrim, scrim.withValues(alpha: 0)],
                        stops: const [0, 0.8, 1],
                      )
                    : null,
              ),
              child: OverflowBox(
                alignment: alignment,
                minWidth: width,
                maxWidth: width,
                minHeight: height,
                maxHeight: height,
                child: FocusBounds(
                  visible: _visible,
                  // On the right the rows are mirrored, to keep their
                  // pictures at the edge.
                  child: Directionality(
                    textDirection: edge == BarEdge.right
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: PaneBox(
                      view: root,
                      tile: (entry) => EntryTile(entry: entry),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
