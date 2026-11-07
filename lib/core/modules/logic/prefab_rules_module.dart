import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Per prefab, the variant and overrides of every instance directly in it.
/// A rule wins over the instance's own values without changing them.
const prefabRulesModule = ModuleType('prefabRules', 'Prefab rules');

extension NodePrefabRules on Node {
  /// `{prefabId: {variant, overrides}}`.
  Map<String, Map<String, Object?>> get prefabRules =>
      overridesFromJson(values(prefabRulesModule.name));

  /// With [rules] as its prefab rules.
  Node withPrefabRules(Map<String, Map<String, Object?>> rules) =>
      withModule(prefabRulesModule.name, rules.isEmpty ? null : rules);

  /// This instance with a parent's [rule] applied over its own variant and
  /// overrides.
  Node underRule(Map<String, Object?>? rule) => rule == null
      ? this
      : copyWith(
          variant: switch (rule['variant']) {
            final String variant => variant,
            _ => variant,
          },
          overrides: overridesOver(
            overrides,
            overridesFromJson(rule['overrides']),
          ),
        );
}
