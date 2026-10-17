import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The variables in scope for the widgets below, by name. Checked before ids.
class TemplateScope extends InheritedWidget {
  const TemplateScope({super.key, required this.values, required super.child});

  final Map<String, Object?> values;

  static Map<String, Object?> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TemplateScope>()?.values ??
      const {};

  @override
  bool updateShouldNotify(TemplateScope oldWidget) =>
      !mapEquals(values, oldWidget.values);
}
