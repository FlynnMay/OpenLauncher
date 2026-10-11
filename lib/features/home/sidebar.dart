import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/component_view.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// Sidebars to keep open and shown even when empty. Used by the editor.
class SidebarHold extends InheritedWidget {
  const SidebarHold({super.key, required this.ids, required super.child});

  final Set<String> ids;

  @override
  bool updateShouldNotify(SidebarHold oldWidget) =>
      !ids.containsAll(oldWidget.ids) || !oldWidget.ids.containsAll(ids);
}

/// A pane on a screen edge that opens while it has the focus and otherwise
/// shows a strip or nothing. Always laid out at its open size, so its
/// contents do not move as it opens.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.panel, this.onOpen});

  final Panel panel;

  /// Called when it starts opening (true) or closing.
  final void Function(bool open)? onOpen;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  /// Duration of the contents' own reveal.
  static const _revealMs = 150;

  final _box = GlobalKey(), _contents = GlobalKey();

  /// 0 closed to 1 open, covering both the bar opening and its contents
  /// appearing.
  late final _opened = AnimationController(vsync: this);
  bool _focused = false, _held = false;

  /// The last value passed to [Sidebar.onOpen].
  bool? _told;

  Panel get _panel => widget.panel;

  /// The `opening` and `reveal` rules.
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

  /// Opens or closes to match the focus and [SidebarHold].
  void _sync() {
    final open = _focused || _held;
    if (open != _told) {
      _told = open;
      // Deferred: found out during build.
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

  /// The visible part of the sidebar, in global coordinates.
  Rect? _visible() => switch (_box.currentContext?.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  /// [tile] with the reveal animation applied.
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
    if (widget.panel.isEmpty && !_held) return const SizedBox.shrink();
    final edge = panel.edge!;
    final alignment = switch (edge) {
      BarEdge.left => Alignment.centerLeft,
      BarEdge.right => Alignment.centerRight,
      BarEdge.top => Alignment.topCenter,
      BarEdge.bottom => Alignment.bottomCenter,
    };
    final root = widget.panel.root;
    return LayoutBuilder(
      builder: (context, screen) {
        // Clamped to the screen.
        final width = panel.openWidth.clamp(0.0, screen.maxWidth);
        final height = panel.openHeight.clamp(0.0, screen.maxHeight);
        final across = panel.opensAcross;
        final full = across ? width : height;
        final closed = panel.closedSize.clamp(0.0, full);
        // Keyed so it keeps its state when the fade wrapper changes.
        final contents = FocusBounds(
          key: _contents,
          visible: _visible,
          // Mirrored on the right, to keep pictures at the edge.
          child: Directionality(
            textDirection: edge == BarEdge.right
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: PaneBox(
              pane: root,
              tile: (entry) =>
                  _appearing(ComponentView(component: entry), alignment),
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
                // A fading bar is at full size from the start.
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
                  // A scrim towards the home screen, unless the pane has a
                  // background.
                  decoration: BoxDecoration(
                    gradient: root.box.isEmpty
                        ? LinearGradient(
                            begin: alignment,
                            end: -alignment,
                            colors: [scrim, scrim, scrim.withValues(alpha: 0)],
                            stops: const [0, 0.8, 1],
                          )
                        : null,
                  ),
                  child: _Faded(
                    // Everything but the closed strip.
                    amount: fading && open > 0 ? open : 1,
                    from: alignment,
                    kept: strip,
                    child: OverflowBox(
                      // Aligned to its edge it is uncovered; to the other
                      // side it slides in.
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

/// [child] faded to [amount], except the first [kept] pixels from [from].
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
