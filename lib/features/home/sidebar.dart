import 'dart:math';

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
  const Sidebar({super.key, required this.view, this.onOpen});

  final PanelView view;

  /// Told when it starts to open (true) and to close: what its `open`
  /// variable is kept by.
  final void Function(bool open)? onOpen;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  /// How long what is in it takes to appear, where that has a time of its
  /// own.
  static const _revealMs = 150;

  final _box = GlobalKey(), _contents = GlobalKey();

  /// 0 closed to 1 open, taking in both the sidebar's opening and what is
  /// in it appearing.
  late final _opened = AnimationController(vsync: this);
  bool _focused = false, _held = false;

  /// What was last told of it.
  bool? _told;

  Panel get _panel => widget.view.panel;

  /// How long the sidebar itself takes to open.
  /// How it comes open and how what is in it appears, as its rules name
  /// them.
  Object? get _opening => _panel.rule('opening');
  Object? get _reveal => _panel.rule('reveal');

  int get _barMs => switch (_opening) {
    'slide' || 'fade' => 200,
    'instant' => 0,
    _ => FocusTile.duration.inMilliseconds,
  };

  int get _totalMs => switch (_reveal) {
    'late' => _barMs + _revealMs,
    'fade' || 'slide' => max(_barMs, _revealMs),
    _ => _barMs,
  };

  /// How far open the sidebar is, 0 to 1.
  double get _barOpen {
    final at = _opened.value * _totalMs;
    if (_barMs == 0) return at > 0 || _opened.value == 1 ? 1 : 0;
    return Curves.easeOut.transform((at / _barMs).clamp(0, 1));
  }

  /// How far what is in it has appeared, 0 to 1.
  double get _revealed => switch (_reveal) {
    'late' => ((_opened.value * _totalMs - _barMs) / _revealMs).clamp(0, 1),
    'fade' || 'slide' => Curves.easeOut.transform(_opened.value),
    _ => 1,
  };

  /// Sets it opening or closing, to match the focus and the hold.
  void _sync() {
    final open = _focused || _held;
    if (open != _told) {
      _told = open;
      // Not while building, which is when a hold is found out.
      Future.microtask(() {
        if (mounted) widget.onOpen?.call(open);
      });
    }
    if (_totalMs == 0) {
      _opened.value = open ? 1 : 0;
      return;
    }
    _opened.duration = Duration(milliseconds: _totalMs);
    open ? _opened.forward() : _opened.reverse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _held =
        context.dependOnInheritedWidgetOfExactType<SidebarHold>()?.ids.contains(
          _panel.id,
        ) ??
        false;
    _sync();
  }

  @override
  void dispose() {
    _opened.dispose();
    super.dispose();
  }

  /// What of the sidebar can be seen, on the display.
  Rect? _visible() => switch (_box.currentContext?.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  /// [tile] appearing the way what is in this sidebar does.
  Widget _appearing(Widget tile, Alignment edge) => _reveal == 'always'
      ? tile
      : AnimatedBuilder(
          animation: _opened,
          child: tile,
          builder: (context, tile) {
            final shown = _revealed;
            return Opacity(
              opacity: shown,
              child: _reveal == 'slide'
                  ? Transform.translate(
                      offset: Offset(edge.x, edge.y) * (28 * (1 - shown)),
                      child: tile,
                    )
                  : tile,
            );
          },
        );

  @override
  Widget build(BuildContext context) {
    final panel = _panel;
    // With nothing in it there is nothing to show or to go to.
    if (widget.view.isEmpty && !_held) return const SizedBox.shrink();
    final edge = panel.edge!;
    final alignment = switch (edge) {
      BarEdge.left => Alignment.centerLeft,
      BarEdge.right => Alignment.centerRight,
      BarEdge.top => Alignment.topCenter,
      BarEdge.bottom => Alignment.bottomCenter,
    };
    final root = widget.view.root;
    return LayoutBuilder(
      builder: (context, screen) {
        // As big as it is set to be, and no bigger than the screen.
        final width = panel.openWidth.clamp(0.0, screen.maxWidth);
        final height = panel.openHeight.clamp(0.0, screen.maxHeight);
        final across = panel.opensAcross;
        final full = across ? width : height;
        final closed = panel.closedSize.clamp(0.0, full);
        // Keyed, to stay as it is when the fading comes and goes around it.
        final contents = FocusBounds(
          key: _contents,
          visible: _visible,
          // On the right the rows are mirrored, to keep their pictures at
          // the edge.
          child: Directionality(
            textDirection: edge == BarEdge.right
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: PaneBox(
              view: root,
              tile: (entry) => _appearing(EntryTile(entry: entry), alignment),
            ),
          ),
        );
        return Align(
          alignment: alignment,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (inside) {
              _focused = inside;
              _sync();
            },
            child: AnimatedBuilder(
              animation: _opened,
              child: contents,
              builder: (context, contents) {
                final open = _barOpen;
                final fading = _opening == 'fade';
                // Fading in, it is at its open size from the start.
                final shown = fading
                    ? (open > 0 ? full : closed)
                    : closed + (full - closed) * open;
                final scrim = Colors.black.withValues(alpha: 0.94 * open);
                final strip = full == 0 ? 0.0 : closed / full;
                return Container(
                  key: _box,
                  width: across ? shown : width,
                  height: across ? height : shown,
                  clipBehavior: Clip.hardEdge,
                  // Fades into the home screen on the side it opens
                  // towards, unless the pane has a background of its own.
                  decoration: BoxDecoration(
                    gradient: root.pane.box.isEmpty
                        ? LinearGradient(
                            begin: alignment,
                            end: -alignment,
                            colors: [scrim, scrim, scrim.withValues(alpha: 0)],
                            stops: const [0, 0.8, 1],
                          )
                        : null,
                  ),
                  child: _Faded(
                    // All but the strip that shows while it is closed.
                    amount: fading && open > 0 ? open : 1,
                    from: alignment,
                    kept: strip,
                    child: OverflowBox(
                      // Laid out at its open size whatever of it shows:
                      // held to its edge it is uncovered, held to the
                      // other side it is carried in.
                      alignment: _opening == 'slide' ? -alignment : alignment,
                      minWidth: width,
                      maxWidth: width,
                      minHeight: height,
                      maxHeight: height,
                      child: contents,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// [child] seen through by [amount] (1 is not at all), except for the
/// first [kept] of it measured from the edge [from], which stays as it is.
class _Faded extends StatelessWidget {
  const _Faded({
    required this.amount,
    required this.from,
    required this.kept,
    required this.child,
  });

  final double amount, kept;
  final Alignment from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (amount >= 1) return child;
    final rest = Colors.white.withValues(alpha: amount);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: from,
        end: -from,
        colors: [Colors.white, Colors.white, rest, rest],
        stops: [0, kept, kept, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}
