import 'package:flutter/material.dart';

/// A switch that can also show mixed.
class TickBox extends StatelessWidget {
  const TickBox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    tristate: value == null,
    title: Text(label),
    value: value,
    // From mixed, a press turns it on.
    onChanged: (next) => onChanged(next ?? true),
  );
}
