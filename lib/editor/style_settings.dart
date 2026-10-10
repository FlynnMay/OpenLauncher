import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';

/// The look of one or more boxes: background colours, the direction of a
/// gradient, and a border. Each part is changed by itself, so that giving
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

  void _fill(List<int> colors) => onChanged(
    (own) => BoxStyle(colors: colors, angle: own.angle, border: own.border),
  );

  @override
  Widget build(BuildContext context) {
    final style = styles.first;
    return Section('Colours', [
      LabelledRow(
        _same((style) => style.colors) ? 'Background' : 'Background\n(mixed)',
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (index, colour) in style.colors.indexed)
              ColourChip(
                colour: colour,
                onChanged: (next) => _fill(
                  [...style.colors]..replaceRange(index, index + 1, [?next]),
                ),
              ),
            if (style.colors.length < BoxStyle.maxColors)
              ColourChip(
                colour: null,
                tooltip: style.colors.isEmpty
                    ? 'Give it a background colour'
                    : 'Add a colour, for a gradient',
                onChanged: (next) => _fill([...style.colors, ?next]),
              ),
          ],
        ),
      ),
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
              (own) =>
                  BoxStyle(colors: own.colors, angle: own.angle, border: next),
            ),
          ),
        ),
      ),
    ]);
  }
}
