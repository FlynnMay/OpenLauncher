import 'package:flutter/material.dart';

class SlideBar extends StatefulWidget {
  const SlideBar({
    super.key,
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value, max;
  final int divisions;

  /// The label shown while dragging.
  final String Function(double value) label;
  final void Function(double value) onChanged;

  @override
  State<SlideBar> createState() => _SlideBarState();
}

class _SlideBarState extends State<SlideBar> {
  /// The value while dragging; committed on release.
  double? _held;

  @override
  Widget build(BuildContext context) => Slider(
    value: (_held ?? widget.value).clamp(0, widget.max),
    max: widget.max,
    divisions: widget.divisions,
    label: widget.label(_held ?? widget.value),
    onChanged: (value) => setState(() => _held = value),
    onChangeEnd: (value) {
      setState(() => _held = null);
      widget.onChanged(value);
    },
  );
}
