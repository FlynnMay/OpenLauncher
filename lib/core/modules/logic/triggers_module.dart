import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// What it does when pressed, held, focused, shown or hidden: per trigger, a
/// chain of actions.
const triggersModule = ModuleType('triggers', 'Triggers');

final _parsed = Expando<Triggers>();

extension NodeTriggers on Node {
  Triggers get on => switch (values(triggersModule.name)) {
    final values? => _parsed[values] ??= triggersFromJson(values),
    null => const {},
  };

  /// With [on] as its triggers.
  Node triggered(Triggers on) =>
      withModule(triggersModule.name, on.isEmpty ? null : triggersToJson(on));
}
