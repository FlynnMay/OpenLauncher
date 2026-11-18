import 'package:openlauncher_domain/entities/entity_action.dart';
import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// What it can be told to do: per name, the operation it runs and the
/// arguments it gives it.
const actionsModule = ModuleType(
  'actions',
  'Actions',
  use: ModuleUse.generated,
);

final _parsed = Expando<Map<String, EntityAction>>();

extension NodeActions on Node {
  Map<String, EntityAction> get actions => switch (values(actionsModule.name)) {
    final values? => _parsed[values] ??= {
      for (final MapEntry(:key, :value) in values.entries)
        key: ?EntityAction.fromJson(value),
    },
    null => const {},
  };

  /// With [actions] as its actions.
  Node withActions(Map<String, EntityAction> actions) => withModule(
    actionsModule.name,
    actions.isEmpty
        ? null
        : {
            for (final MapEntry(:key, :value) in actions.entries)
              key: value.toJson(),
          },
  );
}
