import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/nodes/node.dart';

const layoutGone = 'That layout is gone.';

/// An edit to nodes. Its inverse is whatever put back the children it
/// changed, so no edit has to know how to undo itself.
abstract class NodeEdit extends Command {
  const NodeEdit();

  @override
  Command inverse(Layout before) =>
      RestoreChildren.between(before, apply(before));
}

/// Removes nodes and what they hold, with the instances handed them. One
/// command so that one undo brings back everything a selection took.
class RemoveNodes extends NodeEdit {
  const RemoveNodes(this.ids);

  factory RemoveNodes.fromJson(Json json) => RemoveNodes([
    for (final id in jsonRequired<List<Object?>>(json, 'ids'))
      if (id is String) id,
  ]);

  static const typeName = 'node.remove';

  final List<String> ids;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (!ids.any((id) => layout.node(id) != null)) {
      throw const CommandRefused('There is nothing to remove.');
    }
    return ids.fold(layout, removeItem);
  }

  @override
  Map<String, Object?> toJson() => {'type': type, 'ids': ids};
}

/// Moves [item] to [drop], or adds it there. [opens] is the docked container
/// a new instance opens.
class DropNode extends NodeEdit {
  const DropNode(this.item, this.drop, {this.opens});

  factory DropNode.fromJson(Json json) => DropNode(
    Node.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'item')),
    Drop.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'drop').cast()),
    opens: switch (json['opens']) {
      final Map<Object?, Object?> opens => Node.fromJson(opens),
      _ => null,
    },
  );

  static const typeName = 'node.drop';

  final Node item;
  final Drop drop;
  final Node? opens;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (refusal(layout, item, drop.container) case final reason?) {
      throw CommandRefused(reason);
    }
    return dropItem(layout, item, drop, opens: opens);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'item': item.toJson(),
    'drop': drop.toJson(),
    if (opens != null) 'opens': opens!.toJson(),
  };
}

/// Containers' children put back as they were, and the entities marked
/// removed if that changed. What a container's children hold is kept as it
/// is now, so another editor's work inside them survives.
class RestoreChildren extends NodeEdit {
  const RestoreChildren(this.children, {this.removed});

  factory RestoreChildren.fromJson(Json json) => RestoreChildren(
    {
      for (final MapEntry(:key, :value) in jsonRequired<Map<Object?, Object?>>(
        json,
        'children',
      ).entries)
        '$key': [
          for (final child in value as List<Object?>)
            Node.fromJson(child! as Map<Object?, Object?>),
        ],
    },
    removed: switch (json['removed']) {
      final List<Object?> removed => {...removed.whereType<String>()},
      _ => null,
    },
  );

  /// What turns [to] back into [from]: the children that differ.
  factory RestoreChildren.between(Layout from, Layout to) {
    final after = {for (final node in to.all) node.id: node};
    final changed = <String, List<Node>>{};
    for (final before in from.all) {
      final now = after[before.id];
      if (now != null && !_sameChildren(before.children, now.children)) {
        changed[before.id] = before.children;
      }
    }
    return RestoreChildren(
      changed,
      removed: _sameSet(from.removed, to.removed) ? null : from.removed,
    );
  }

  static const typeName = 'node.restore';

  /// The children of each container, by its id.
  final Map<String, List<Node>> children;

  /// Null leaves the removed entities as they are.
  final Set<String>? removed;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    var next = layout;
    for (final MapEntry(:key, :value) in children.entries) {
      next = _withChildren(next, key, value);
    }
    return removed == null ? next : next.copyWith(removed: removed);
  }

  static Layout _withChildren(Layout layout, String id, List<Node> previous) {
    final container =
        layout.node(id) ?? (throw const CommandRefused(layoutGone));
    final current = {for (final child in container.children) child.id: child};
    return layout.withContainer(
      id,
      (container) => container.copyWith(
        children: [
          for (final child in previous) _holdingNow(child, current[child.id]),
        ],
      ),
    );
  }

  static Node _holdingNow(Node previous, Node? current) => current == null
      ? previous
      : previous.copyWith(children: current.children);

  static bool _sameChildren(List<Node> a, List<Node> b) =>
      a.length == b.length &&
      a.indexed.every((entry) => _sameShell(entry.$2, b[entry.$1]));

  /// Whether two nodes are alike, not counting what they hold.
  static bool _sameShell(Node a, Node b) => jsonEquals(
    a.copyWith(children: const []).toJson(),
    b.copyWith(children: const []).toJson(),
  );

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'children': {
      for (final MapEntry(:key, :value) in children.entries)
        key: [for (final child in value) child.toJson()],
    },
    if (removed != null) 'removed': removed!.toList()..sort(),
  };
}

/// The commands about nodes, by the name they go by in JSON.
final Map<String, CommandReader> nodeCommandReaders = {
  RemoveNodes.typeName: RemoveNodes.fromJson,
  DropNode.typeName: DropNode.fromJson,
  RestoreChildren.typeName: RestoreChildren.fromJson,
};
