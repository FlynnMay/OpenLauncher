import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls.dart';

/// Corner radii: one for all, or each separately.
class CornerSettings extends StatefulWidget {
  const CornerSettings({
    super.key,
    required this.corners,
    required this.usual,
    required this.max,
    required this.onChanged,
    this.label = 'Corners',
  });

  final String label;

  /// Top left, top right, bottom right, bottom left; null for the default.
  final List<double>? corners;

  final double usual, max;

  /// Null restores the default.
  final void Function(List<double>? corners) onChanged;

  @override
  State<CornerSettings> createState() => _CornerSettingsState();
}

class _CornerSettingsState extends State<CornerSettings> {
  static const _names = [
    'Top left',
    'Top right',
    'Bottom right',
    'Bottom left',
  ];

  /// Whether corners are edited separately; starts true if they differ.
  late bool _each = _differ;

  bool get _differ =>
      widget.corners?.toSet().length != 1 && widget.corners != null;

  @override
  Widget build(BuildContext context) {
    final corners = widget.corners;
    final all = corners ?? List.filled(4, widget.usual);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NumberStepper(
          label: widget.label,
          // Below zero means default; null means mixed.
          value: corners == null
              ? -1
              : _differ
              ? null
              : corners.first,
          usual: 'Usual',
          min: 0,
          max: widget.max.round(),
          step: 2,
          onChanged: (round) =>
              widget.onChanged(round < 0 ? null : List.filled(4, round * 1.0)),
        ),
        TickBox(
          label: 'Each corner by itself',
          value: _each,
          onChanged: (each) => setState(() => _each = each),
        ),
        if (_each)
          for (final (index, name) in _names.indexed)
            NumberStepper(
              label: name,
              value: all[index],
              min: 0,
              max: widget.max.round(),
              step: 2,
              onChanged: (round) =>
                  widget.onChanged([...all]..[index] = round * 1.0),
            ),
      ],
    );
  }
}
