import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Lets the remote focus and press it, and says how the focus shows.
class FocusModule extends ModuleType {
  const FocusModule()
    : super(
        'focus',
        'Focus',
        fields: const [
          Field(
            'scale',
            'Focused size %',
            FieldKind.number,
            defaultValue: defaultScale,
            min: 100,
            max: 150,
          ),
          Field('target', 'Shows the focus', FieldKind.text),
          Field('bare', 'Bare frame', FieldKind.template, defaultValue: 'true'),
        ],
      );

  /// How much it grows when focused, in percent.
  static const defaultScale = 108;
}

const focusModule = FocusModule();

extension NodeFocus on Node {
  ModuleValues get _focus => values(focusModule.name) ?? const {};

  bool get focusable => has(focusModule.name);

  /// How much it grows when focused, as a factor.
  double get focusScale => switch (_focus['scale']) {
    final num percent => percent / 100,
    _ => FocusModule.defaultScale / 100,
  };

  /// The part that draws the focus, by id; null for the whole node.
  String? get focusTarget => switch (_focus['target']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  };

  /// Whether its focus frame has no background, only a faint wash when
  /// focused (for line art). May be a template.
  Object? get focusBare => _focus['bare'] ?? true;
}
