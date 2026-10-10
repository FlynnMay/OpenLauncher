import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';

/// A strip of small tiles along a screen edge that widens to show their
/// names while the focus is inside it. It opens over the home screen rather
/// than pushing it aside.
class Rail extends StatefulWidget {
  const Rail({super.key, required this.view, required this.onLeft});

  final PanelView view;

  /// True for the left edge, false for the right.
  final bool onLeft;

  /// The width of the closed rail; the home screen keeps this much clear.
  static const closedWidth = _outer + _pictureWidth + _inner;
  static const _openWidth = 260.0;
  static const _tileHeight = 36.0;
  static const _pictureWidth = _tileHeight * 16 / 9;

  /// Overscan margin on the screen side, a little air on the other.
  static const _outer = 24.0, _inner = 10.0;

  @override
  State<Rail> createState() => _RailState();
}

class _RailState extends State<Rail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.view.root.entries;
    final scrim = Colors.black.withValues(alpha: _open ? 0.94 : 0);
    final edge = widget.onLeft ? Alignment.centerLeft : Alignment.centerRight;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (inside) => setState(() => _open = inside),
      child: AnimatedContainer(
        duration: FocusTile.duration,
        curve: Curves.easeOut,
        width: _open ? Rail._openWidth : Rail.closedWidth,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: edge,
            end: -edge,
            colors: [scrim, scrim, scrim.withValues(alpha: 0)],
            stops: const [0, 0.8, 1],
          ),
        ),
        // Laid out at its open width whatever the width is animating to,
        // so nothing reflows on the way. On the right edge the rows are
        // mirrored, to keep the pictures outermost.
        child: OverflowBox(
          alignment: edge,
          minWidth: Rail._openWidth,
          maxWidth: Rail._openWidth,
          child: PaneScope(
            panes: [widget.view.root.pane.id],
            child: Directionality(
              textDirection: widget.onLeft
                  ? TextDirection.ltr
                  : TextDirection.rtl,
              child: ListView.separated(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Rail._outer,
                  27,
                  Rail._inner,
                  27,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final tile = EntryTile(
                    entry: entry,
                    style: TileStyle.rail,
                    compact: !_open,
                  );
                  return SizedBox(
                    key: ValueKey(entry.item.id),
                    height: entry is WidgetEntry
                        ? Rail._tileHeight * entry.item.h.clamp(1, 3)
                        : Rail._tileHeight,
                    // Closed, a row is only as wide as its picture: the D-pad
                    // finds its way by where things are, and a row reaching
                    // under the home screen would be in the way. The tile
                    // keeps its place in the tree, and so the focus.
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        width: _open ? double.infinity : Rail._pictureWidth,
                        height: double.infinity,
                        child: tile,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
