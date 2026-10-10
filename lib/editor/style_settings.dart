import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/gradient_bar.dart';

/// The look of one or more boxes: background colours, where along a
/// gradient each one sits and which way it runs, and a border. Each part is changed by itself, so that giving
/// several things the same border leaves each its own background.
class StyleSettings extends StatelessWidget {
  const StyleSettings({
    super.key,
    required this.styles,
    required this.onChanged,
  });

  /// The look of each thing being edited; the first is the one shown.
  final List<BoxStyle> styles;

  /// Called with how each thing's own look is to change.
  final void Function(BoxStyle Function(BoxStyle own) change) onChanged;

  bool _same(Object? Function(BoxStyle style) part) =>
      styles.map((style) => jsonEncode(part(style))).toSet().length == 1;

  void _fill(List<int> colors, [List<double> stops = const []]) => onChanged(
    (own) => BoxStyle(
      colors: colors,
      stops: stops,
      angle: own.angle,
      border: own.border,
    ),
  );

  static Object? _background(BoxStyle style) => [style.colors, style.stops];

  @override
  Widget build(BuildContext context) {
    final style = styles.first;
    return Section('Colours', [
      if (style.colors.length < 2)
        LabelledRow(
          _same(_background) ? 'Background' : 'Background\n(mixed)',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final colour in style.colors)
                ColourChip(colour: colour, onChanged: (next) => _fill([?next])),
              ColourChip(
                colour: null,
                tooltip: style.colors.isEmpty
                    ? 'Give it a background colour'
                    : 'Add a colour, for a gradient',
                onChanged: (next) => _fill([...style.colors, ?next]),
              ),
            ],
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(_same(_background) ? 'Background' : 'Background (mixed)'),
        ),
        GradientBar(
          stops: [
            for (final (index, at) in style.positions.indexed)
              (colour: style.colors[index], at: at),
          ],
          max: BoxStyle.maxColors,
          onChanged: (stops) => _fill(
            [for (final stop in stops) stop.colour],
            [
              if (stops.length > 1)
                for (final stop in stops) stop.at,
            ],
          ),
        ),
      ],
      if (style.colors.length > 1)
        LabelledRow(
          'Direction',
          SlideBar(
            value: style.angle * 1.0,
            max: 345,
            divisions: 23,
            label: (angle) => '${angle.round()}°',
            onChanged: (angle) => onChanged(
              (own) => BoxStyle(
                colors: own.colors,
                stops: own.stops,
                angle: angle.round(),
                border: own.border,
              ),
            ),
          ),
        ),
      LabelledRow(
        _same((style) => style.border) ? 'Border' : 'Border\n(mixed)',
        Align(
          alignment: Alignment.centerLeft,
          child: ColourChip(
            colour: style.border,
            tooltip: 'Give it a border',
            onChanged: (next) => onChanged(
              (own) => BoxStyle(
                colors: own.colors,
                stops: own.stops,
                angle: own.angle,
                border: next,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
