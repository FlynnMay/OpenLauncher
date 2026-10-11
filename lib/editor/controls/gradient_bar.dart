import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/colour_picker.dart';
import 'package:openlauncher/editor/controls/labelled_row.dart';
import 'package:openlauncher/editor/controls/number_field.dart';

/// One gradient colour (0xAARRGGBB) and its position, 0 to 1.
typedef ColourStop = ({int colour, double at});

/// A gradient bar with a draggable handle per colour. Tapping the bar adds a
/// colour; the selected handle's colour and position are edited below.
/// Handles cannot pass their neighbours.
class GradientBar extends StatefulWidget {
  const GradientBar({
    super.key,
    required this.stops,
    required this.onChanged,
    this.max = 8,
  });

  final List<ColourStop> stops;

  /// Maximum number of colours.
  final int max;

  /// Called on release and on any other change.
  final void Function(List<ColourStop> stops) onChanged;

  /// Half a handle's width.
  static const inset = 11.0;

  @override
  State<GradientBar> createState() => _GradientBarState();
}

class _GradientBarState extends State<GradientBar> {
  static const _barHeight = 28.0, _handleHeight = 22.0, _overlap = 6.0;

  /// The selected handle.
  var _picked = 0;

  /// The dragged handle's position before clamping; committed on release.
  double? _held;

  /// Pointer and handle positions at drag start.
  var _grabbed = 0.0, _from = 0.0;

  int get _index => min(_picked, widget.stops.length - 1);

  /// The range the handle at [index] can move in.
  (double, double) _room(int index) => (
    index == 0 ? 0 : widget.stops[index - 1].at,
    index == widget.stops.length - 1 ? 1 : widget.stops[index + 1].at,
  );

  /// The stops as drawn, including the dragged one.
  List<ColourStop> get _shown {
    final held = _held;
    if (held == null) return widget.stops;
    final (from, to) = _room(_index);
    return [
      for (final (index, stop) in widget.stops.indexed)
        index == _index
            ? (colour: stop.colour, at: _whole(held.clamp(from, to)))
            : stop,
    ];
  }

  /// Rounded to a whole percent.
  static double _whole(double at) => (at * 100).round() / 100;

  void _send(List<ColourStop> stops) {
    // Keep them ascending.
    var last = 0.0;
    widget.onChanged([
      for (final stop in stops)
        (colour: stop.colour, at: last = stop.at.clamp(last, 1.0)),
    ]);
  }

  void _add(double at) {
    final stops = widget.stops;
    if (stops.length >= widget.max) return;
    final after = stops.indexWhere((stop) => stop.at > at);
    final index = after < 0 ? stops.length : after;
    // The gradient's colour at that point, so nothing jumps.
    final Color colour;
    if (index == 0) {
      colour = Color(stops.first.colour);
    } else if (index == stops.length) {
      colour = Color(stops.last.colour);
    } else {
      final a = stops[index - 1], b = stops[index];
      colour = Color.lerp(
        Color(a.colour),
        Color(b.colour),
        b.at == a.at ? 0 : (at - a.at) / (b.at - a.at),
      )!;
    }
    setState(() => _picked = index);
    _send([...stops]..insert(index, (colour: colour.toARGB32(), at: at)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    final picked = shown[_index];
    final (from, to) = _room(_index);
    final lowest = (from * 100 - 1e-6).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final span = box.maxWidth - GradientBar.inset * 2;
            return SizedBox(
              height: _barHeight + _handleHeight - _overlap,
              child: Stack(
                children: [
                  Positioned(
                    left: GradientBar.inset,
                    width: span,
                    top: 0,
                    height: _barHeight,
                    child: Tooltip(
                      message: widget.stops.length < widget.max
                          ? 'Click to add a colour'
                          : 'Maximum colours reached',
                      waitDuration: const Duration(milliseconds: 600),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (tap) => _add(
                          _whole((tap.localPosition.dx / span).clamp(0, 1)),
                        ),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outline),
                          ),
                          child: CustomPaint(
                            painter: const Checks(),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    for (final stop in shown)
                                      Color(stop.colour),
                                  ],
                                  stops: [for (final stop in shown) stop.at],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final (index, stop) in shown.indexed)
                    Positioned(
                      key: ValueKey(index),
                      left: stop.at * span,
                      width: GradientBar.inset * 2,
                      top: _barHeight - _overlap,
                      height: _handleHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _picked = index),
                        // From where it was pressed, so that the handle
                        // stays under the pointer.
                        dragStartBehavior: DragStartBehavior.down,
                        onHorizontalDragStart: (drag) => setState(() {
                          _picked = index;
                          _grabbed = drag.globalPosition.dx;
                          _from = widget.stops[index].at;
                          _held = _from;
                        }),
                        onHorizontalDragUpdate: (drag) => setState(
                          () => _held =
                              _from +
                              (drag.globalPosition.dx - _grabbed) / span,
                        ),
                        onHorizontalDragEnd: (_) {
                          final moved = _shown;
                          setState(() => _held = null);
                          _send(moved);
                        },
                        onHorizontalDragCancel: () =>
                            setState(() => _held = null),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: index == _index
                                  ? scheme.primary
                                  : scheme.outline,
                              width: index == _index ? 3 : 1,
                            ),
                          ),
                          child: CustomPaint(
                            painter: const Checks(),
                            child: ColoredBox(color: Color(stop.colour)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        LabelledRow(
          'Colour ${_index + 1}',
          Align(
            alignment: Alignment.centerLeft,
            child: ColourChip(
              colour: picked.colour,
              onChanged: (next) => _send(
                [...widget.stops]..replaceRange(_index, _index + 1, [
                  if (next != null) (colour: next, at: picked.at),
                ]),
              ),
            ),
          ),
        ),
        NumberField(
          label: 'Position %',
          value: (picked.at * 100).roundToDouble(),
          min: lowest,
          max: max(lowest, (to * 100 + 1e-6).floor()),
          onChanged: (percent) => _send(
            [...widget.stops]
              ..[_index] = (colour: picked.colour, at: percent / 100),
          ),
        ),
      ],
    );
  }
}
