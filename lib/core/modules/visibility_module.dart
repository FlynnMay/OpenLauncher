import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Whether a node is drawn, and whether the others close up when it is not.
/// Every node has it. `visible` is `false` for hidden, or an expression
/// (`{{source.title}}`) that must hold, read in the node's own scope; absent,
/// it is always shown.
class VisibilityModule extends ModuleType {
  const VisibilityModule()
    : super(
        'visibility',
        'Visibility',
        mandatory: true,
        // `visible` is edited by the module's own editor.
        fields: const [
          Field('visible', 'Visible', FieldKind.template, defaultValue: true),
          Field('keep', 'Keep space when hidden', FieldKind.toggle),
        ],
      );

  /// What an override says to go back to the default; once applied it is
  /// gone.
  static bool _default(String key, Object? value) => switch (key) {
    'visible' => value == true,
    'keep' => value == false,
    _ => false,
  };

  @override
  ModuleValues merge(ModuleValues under, ModuleValues over) => {
    for (final MapEntry(:key, :value) in mergeValues(under, over).entries)
      if (!_default(key, value)) key: value,
  };
}

const visibilityModule = VisibilityModule();

extension NodeVisibility on Node {
  ModuleValues get _visibility => values(visibilityModule.name) ?? const {};

  /// Always hidden.
  bool get hidden => _visibility['visible'] == false;

  /// The expression that must hold for it to be shown, if it has one.
  String? get visibleWhen => switch (_visibility['visible']) {
    final String expression when expression.isNotEmpty => expression,
    _ => null,
  };

  /// Keeps its place while hidden, in a row, column or cells.
  bool get keep => _visibility['keep'] == true;

  /// Shown always, hidden (`false`), or shown when [visible] holds; null or
  /// `true` is the default.
  Node withVisible(Object? visible) => _visibilityWith(
    'visible',
    visible == true || visible == '' ? null : visible,
  );

  Node withKeep(bool keep) => _visibilityWith('keep', keep ? true : null);

  /// With [key] set; the module is left out of the save when it says nothing.
  Node _visibilityWith(String key, Object? value) {
    final next = {..._visibility, key: value}
      ..removeWhere((_, value) => value == null);
    return withModule(visibilityModule.name, next.isEmpty ? null : next);
  }
}
