import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';

/// One colour of a gradient, as 0xAARRGGBB, and where along it the colour
/// is at its fullest: 0 at the start to 1 at the end.
typedef ColourStop = ({int colour, double at});

/// A gradient drawn as a bar with a handle under each of its colours. A
/// handle is dragged to where its colour belongs, pressing the bar adds a
/// colour there, and the handle last touched has its colour and its exact
/// place underneath. A handle stays between its neighbours.
class GradientBar extends StatefulWidget {
  const GradientBar({
    super.key,
    required this.stops,
    required this.onChanged,
    this.max = 8,
  });

  /// In order along the gradient.
  final List<ColourStop> stops;

  /// The most colours it may be given.
  final int max;

  /// Called with all the stops, on letting go of a handle and on any other
  /// change. Taking the last colours away is allowed: the list gets short.
  final void Function(List<ColourStop> stops) onChanged;

  /// Half a handle: how far the bar stops short of either end.
  static const inset = 11.0;

  @override
  State<GradientBar> createState() => _GradientBarState();
}

class _GradientBarState extends State<GradientBar> {
  static const _barHeight = 28.0, _handleHeight = 22.0, _overlap = 6.0;

  /// The handle whose details are shown.
  var _picked = 0;

  /// Where the picked handle is while it is held, before being kept
  /// between its neighbours; the change is made on letting go.
  double? _held;

  /// Where the pointer took hold of it, and where the handle was then.
  var _grabbed = 0.0, _from = 0.0;

  int get _index => min(_picked, widget.stops.length - 1);

  /// How far the handle at [index] may go either way.
  (double, double) _room(int index) => (
    index == 0 ? 0 : widget.stops[index - 1].at,
    index == widget.stops.length - 1 ? 1 : widget.stops[index + 1].at,
  );

  /// The stops as drawn: the held handle where it has been dragged to.
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

  /// To a whole percent.
  static double _whole(double at) => (at * 100).round() / 100;

  void _send(List<ColourStop> stops) {
    // However they were come by, never one before the one in front of it.
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
    // The colour the gradient already has there, so nothing jumps.
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
                          ? 'Press to add a colour here'
                          : 'No more colours fit',
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
        NumberStepper(
          label: 'Shifts at %',
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
