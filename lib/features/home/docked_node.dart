import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/dock_host.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';

/// Docked containers to keep open and shown even when empty. Used by the editor.
class DockHold extends InheritedWidget {
  const DockHold({super.key, required this.ids, required super.child});

  final Set<String> ids;

  @override
  bool updateShouldNotify(DockHold oldWidget) =>
      !ids.containsAll(oldWidget.ids) || !oldWidget.ids.containsAll(ids);
}

/// A docked pane, on an edge or in the middle. It is open
/// while its `open` variable is set; closed, it shows its `closed` strip or
/// is not there at all. On an edge it is laid out at its open size, so its
/// contents do not move as it opens.
class DockedNode extends ConsumerStatefulWidget {
  const DockedNode({super.key, required this.pane});

  final Node pane;

  @override
  ConsumerState<DockedNode> createState() => _DockedNodeState();
}

class _DockedNodeState extends ConsumerState<DockedNode>
    with SingleTickerProviderStateMixin {
  /// Duration of the contents' own reveal.
  static const _revealMs = 150;

  /// Most of the screen's height one in the middle may take.
  static const _tallest = 0.8;

  final _box = GlobalKey(), _contents = GlobalKey();

  /// 0 closed to 1 open, covering both the pane opening and its contents
  /// appearing.
  late final _opened = AnimationController(vsync: this);
  bool _held = false;

  /// What [_opened] was last sent towards.
  bool? _open;

  /// Given to what is in it each time it opens, so the first tile built
  /// then takes the focus.
  FirstFocus? _first;

  Node get _pane => widget.pane;

  Object? get _opening => _pane.valueOf(dockModule, 'opening');
  Object? get _reveal => _pane.valueOf(dockModule, 'reveal');

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

  /// How far open it is, 0 to 1.
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

  void _sync(bool open) {
    if (open == _open) return;
    _open = open;
    _first = open ? FirstFocus() : null;
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
        context.dependOnInheritedWidgetOfExactType<DockHold>()?.ids.contains(
          _pane.id,
        ) ??
        false;
  }

  @override
  void dispose() {
    _opened.dispose();
    super.dispose();
  }

  /// The part of it that shows, in global coordinates; all of it in place.
  Rect? _visible() => switch ((_box.currentContext ?? _contents.currentContext)
      ?.findRenderObject()) {
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

  /// The pane as drawn: a menu opened for an entity leaves out what cannot
  /// be done to it.
  Node _offered() => subjectOf(ref, _pane.id) == null
      ? _pane
      : offeredIn(
          _pane,
          ref.watch,
          ref.watch(entitiesProvider).value ?? const [],
        );

  /// The pane [shown] in its box. Keyed so it keeps its state as what is
  /// around it changes.
  Widget _contentsOf(Node shown, Alignment from, {bool shrink = false}) {
    final pane = _pane;
    final popup = pane.closeOnPress ? pane.id : null;
    final box = NodeView(
      component: shown,
      screen: true,
      tall: shrink,
      focus: _first,
      popup: popup,
      placeholder: 'Nothing here yet. Add things from the web page.',
      wrap: (_, drawn) => _appearing(drawn, from),
    );
    return FocusBounds(
      key: _contents,
      visible: _visible,
      // A strip on the right is mirrored, to keep its pictures at the edge.
      child: pane.edge == BarEdge.right && pane.closed != null
          ? Directionality(textDirection: TextDirection.rtl, child: box)
          : box,
    );
  }

  /// Runs the focus and blur chains.
  Widget _watched(Widget child) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (inside) {
      if (!mounted) return;
      runChain(
        context,
        ref,
        _pane.on[inside ? Trigger.focus : Trigger.blur] ?? const [],
        _pane.id,
      );
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final pane = _pane;
    final shown = _offered();
    final open =
        _held ||
        ref.watch(
          runtimeVarsProvider.select((all) => all[pane.id]?[openVar] == true),
        );
    _sync(open);
    // An empty pane has no closed strip.
    if (pane.isEmpty && !open) return const SizedBox.shrink();
    final edge = pane.edge;
    final alignment = switch (edge) {
      BarEdge.left => Alignment.centerLeft,
      BarEdge.right => Alignment.centerRight,
      BarEdge.top => Alignment.topCenter,
      BarEdge.bottom => Alignment.bottomCenter,
      null => Alignment.center,
    };
    return LayoutBuilder(
      builder: (context, screen) {
        // Clamped to the screen.
        final width = pane.openWidth.clamp(0.0, screen.maxWidth);
        final tall = pane.openHeight?.clamp(0.0, screen.maxHeight);
        if (edge == null) {
          // In the middle: it only fades. With no height of its own it is
          // as tall as what is in it.
          return AnimatedBuilder(
            animation: _opened,
            child: _contentsOf(shown, alignment, shrink: tall == null),
            builder: (context, contents) {
              final open = _barOpen;
              if (open == 0) return const SizedBox.shrink();
              return Align(
                child: Opacity(
                  opacity: _opening == 'fade' ? open : 1,
                  child: _watched(
                    ConstrainedBox(
                      key: _box,
                      constraints: BoxConstraints(
                        minWidth: width,
                        maxWidth: width,
                        minHeight: tall ?? 0,
                        maxHeight: tall ?? screen.maxHeight * _tallest,
                      ),
                      child: contents,
                    ),
                  ),
                ),
              );
            },
          );
        }
        final height = tall ?? screen.maxHeight;
        final across = pane.opensAcross;
        final full = across ? width : height;
        final closed = (pane.closed ?? 0).clamp(0.0, full);
        return Align(
          alignment: alignment,
          child: _watched(
            AnimatedBuilder(
              animation: _opened,
              child: _contentsOf(shown, alignment),
              builder: (context, contents) {
                final open = _barOpen;
                // Hidden while closed.
                if (pane.hiddenWhenClosed && open == 0) {
                  return const SizedBox.shrink();
                }
                final fading = _opening == 'fade';
                // A fading pane is at full size from the start.
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
                  // A scrim towards the rest of the screen, unless the pane
                  // has a background.
                  decoration: BoxDecoration(
                    gradient: pane.box.isEmpty
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
