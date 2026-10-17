import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';
import 'package:openlauncher/features/modules/variables_drawer.dart';

// What the visual modules share: their values are templates, their style is
// merged over what is inherited.

Color cssColour(Object? css, [Color otherwise = Colors.white]) =>
    switch (BoxStyle.parseColor(css)) {
      null => otherwise,
      final argb => Color(argb),
    };

/// The node's style, under `style` in [values], over the inherited one,
/// evaluated.
Style visualStyle(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> values,
) => readStyle(ref.watch, {
  ...StyleScope.of(context),
  ...styleFromJson(values['style']),
}, TemplateScope.of(context));

/// Evaluates [template] to text.
String visualText(BuildContext context, WidgetRef ref, Object? template) {
  if (template is! String) return template == null ? '' : '$template';
  return valueText(
    readTemplate(ref.watch, template, TemplateScope.of(context)),
  );
}
