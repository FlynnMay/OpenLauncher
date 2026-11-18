import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/modules/logic/actions_module.dart';
import 'package:openlauncher_domain/modules/logic/feed_module.dart';
import 'package:openlauncher_domain/modules/logic/variables_module.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/nodes/node_access.dart';
import 'package:openlauncher_domain/variables/variable.dart';

// This reads and writes the JSON an entity has always had, as a node. It
// stands until the saved shape becomes the node's own.

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// The key of the variable holding the device's own name.
const deviceNameKey = 'name';

/// A node from entity JSON; null unless it has an id. Its `data` becomes
/// public variables, the device's name one of them.
Node? nodeFromEntityJson(Object? json) {
  final entity = Entity.fromJson(json);
  if (entity == null) return null;
  final values = {...entity.data};
  values.putIfAbsent(deviceNameKey, () => entity.name);
  return Node(
        id: entity.id,
        name: entity.label,
        category: entity.category,
        inbox: entity.placed,
      )
      .withVars({
        for (final MapEntry(:key, :value) in values.entries)
          key: Variable(value, access: NodeAccess.public),
      })
      .withFeed(entity.feed)
      .withActions(entity.actions);
}

/// The entity JSON of [node].
Map<String, Object?> entityJsonOf(Node node) {
  final values = {
    for (final MapEntry(:key, :value) in node.vars.entries) key: value.value,
  };
  final deviceName = values.remove(deviceNameKey);
  return Entity(
    id: node.id,
    category: node.category,
    label: node.name,
    name: deviceName is String ? deviceName : null,
    data: values,
    feed: node.feed,
    actions: node.actions,
    placed: node.inbox,
  ).toJson();
}
