import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Lets the remote focus and press it, and says how the focus shows.
const focusModule = ModuleType(
  'focus',
  'Focus',
  fields: [
    Field(
      'scale',
      'Focused size %',
      FieldKind.number,
      min: 100,
      max: 150,
      unset: 'Default',
    ),
    Field('target', 'Shows the focus', FieldKind.text),
    Field('bare', 'Bare frame', FieldKind.template),
  ],
);

extension NodeFocus on Node {
  ModuleValues get _focus => values(focusModule.name) ?? const {};

  bool get focusable => has(focusModule.name);

  /// How much it grows when focused, as a factor; null for the default.
  double? get focusScale => switch (_focus['scale']) {
    final num percent => percent / 100,
    _ => null,
  };

  /// The part that draws the focus, by id; null for the whole node.
  String? get focusTarget => switch (_focus['target']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  };

  /// Whether the target's frame has no background, only a faint wash when
  /// focused (for line art). May be a template.
  Object? get focusBare => _focus['bare'];
}
