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
