import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// Generated fields for style [keys]. Reports one property and its new value,
/// null for the default.
List<Widget> styleFields({
  required Iterable<String> keys,
  required Style style,
  required void Function(String key, Object? value) onChanged,
  double corner = 10,
}) => ruleFields(
  options: stylePropsOf(keys),
  json: style,
  onChanged: onChanged,
  corner: corner,
);

/// Style of one or more things. With several, the first one's values show and
/// a change applies that property to each.
class StyleSettings extends StatelessWidget {
  const StyleSettings({
    super.key,
    required this.keys,
    required this.style,
    required this.onChanged,
    this.corner = 10,
  });

  final Iterable<String> keys;
  final Style style;
  final void Function(String key, Object? value) onChanged;

  /// Default corner radius.
  final double corner;

  @override
  Widget build(BuildContext context) => keys.isEmpty
      ? const SizedBox.shrink()
      : Section(
          'Style',
          styleFields(
            keys: keys,
            style: style,
            onChanged: onChanged,
            corner: corner,
          ),
        );
}
