import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/modules/logic/actions_module.dart';
import 'package:openlauncher_domain/modules/logic/feed_module.dart';
import 'package:openlauncher_domain/modules/logic/variables_module.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/nodes/node_access.dart';
import 'package:openlauncher_domain/variables/variable.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// The key of the variable holding the device's own name.
const deviceNameKey = 'name';

/// What a node that stands for a thing holds. Its static values are public
/// variables, the device's own name apart.
extension NodeData on Node {
  /// Its static values, without the device name.
  Map<String, Object?> get data => {
    for (final MapEntry(:key, :value) in vars.entries)
      if (key != deviceNameKey) key: value.value,
  };

  /// The device's own name for it, else its label.
  String get deviceName => switch (vars[deviceNameKey]?.value) {
    final String name when name.isNotEmpty => name,
    _ => name,
  };

  /// With [more] merged over its static values.
  Node withData(Map<String, Object?> more) => withVars({
    ...vars,
    for (final MapEntry(:key, :value) in more.entries)
      key: Variable(value, access: NodeAccess.public),
  });

  /// With [label] as its name.
  Node withLabel(String label) => copyWith(name: label);

  /// What `{{self...}}` reads for an action of it.
  Map<String, Object?> get self => {
    'id': id,
    'label': name,
    'name': deviceName,
    'category': category,
    ...data,
  };
}

extension NodesById on Iterable<Node> {
  Node? byId(String? id) => where((node) => node.id == id).firstOrNull;
}

/// Whether [a] and [b] are the same nodes, in the same order.
bool sameNodes(List<Node> a, List<Node> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i].toJson()].toString() ==
        [for (var i = 0; i < b.length; i++) b[i].toJson()].toString();

/// A node from entity JSON; null unless it has an id.
Node? nodeFromEntityJson(Object? json) => switch (Entity.fromJson(json)) {
  final entity? => nodeOfEntity(entity),
  null => null,
};

/// The entity JSON of [node].
Map<String, Object?> entityJsonOf(Node node) => entityOfNode(node).toJson();

// ---------------------------------------------------------------------------
// Temporary
// ---------------------------------------------------------------------------

// Until `Entity` is deleted (the last step of the node merge), the entity
// list is made of nodes and handed on as entities. Nothing new should use
// these two.

/// [entity] as a node.
Node nodeOfEntity(Entity entity) =>
    Node(
          id: entity.id,
          name: entity.label,
          category: entity.category,
          inbox: entity.placed,
        )
        .withVars({
          for (final MapEntry(:key, :value) in {
            ...entity.data,
            deviceNameKey: entity.data[deviceNameKey] ?? entity.name,
          }.entries)
            key: Variable(value, access: NodeAccess.public),
        })
        .withFeed(entity.feed)
        .withActions(entity.actions);

/// [node] as an entity.
Entity entityOfNode(Node node) => Entity(
  id: node.id,
  category: node.category,
  label: node.name,
  name: node.deviceName,
  data: node.data,
  feed: node.feed,
  actions: node.actions,
  placed: node.inbox,
);
