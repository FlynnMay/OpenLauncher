import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/screen_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/validation/validation.dart';

const layoutGone = 'That layout is gone.';

/// An edit to nodes. Its inverse is the patch that puts back what it changed,
/// so no edit has to know how to undo itself.
abstract class NodeEdit extends LayoutCommand {
  const NodeEdit();

  @override
  LayoutCommand inverse(Layout before) =>
      PatchLayout.turning(apply(before), before);
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

/// A change to the layout as the difference it makes: the containers whose
/// children changed, the screen roots whose own values changed, and the
/// entities marked removed if that changed. A tool that works out a new layout
/// sends this, so what it did not touch is left as it is, and it can be undone
/// like any command. What a container's children hold is kept as it is now
/// where they are the same nodes, so another editor's work inside survives.
class PatchLayout extends NodeEdit {
  const PatchLayout({
    this.containers = const {},
    this.roots = const {},
    this.removed,
  });

  factory PatchLayout.fromJson(Json json) => PatchLayout(
    containers: {
      for (final MapEntry(:key, :value) in jsonObject(
        json['containers'],
      ).entries)
        key: [
          for (final child in value! as List<Object?>)
            Node.fromJson(child! as Map<Object?, Object?>),
        ],
    },
    roots: {
      for (final MapEntry(:key, :value) in jsonObject(json['roots']).entries)
        key: Node.fromJson(value! as Map<Object?, Object?>),
    },
    removed: switch (json['removed']) {
      final List<Object?> removed => {...removed.whereType<String>()},
      _ => null,
    },
  );

  /// What turns [from] into [into].
  factory PatchLayout.turning(Layout from, Layout into) {
    final before = {for (final node in from.all) node.id: node};
    final containers = <String, List<Node>>{};
    for (final after in into.all) {
      final was = before[after.id];
      if (was != null && !_sameChildren(was.children, after.children)) {
        containers[after.id] = after.children;
      }
    }
    return PatchLayout(
      containers: containers,
      roots: _changedRoots(from, into),
      removed: _sameSet(from.removed, into.removed) ? null : into.removed,
    );
  }

  static const typeName = 'layout.patch';

  /// The children of each container, by its id.
  final Map<String, List<Node>> containers;

  /// The screens' roots that changed, by screen id, without their children.
  final Map<String, Node> roots;

  /// Null leaves the removed entities as they are.
  final Set<String>? removed;

  bool get isEmpty => containers.isEmpty && roots.isEmpty && removed == null;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    var next = layout;
    for (final MapEntry(:key, :value) in roots.entries) {
      next = _withRoot(next, key, value);
    }
    for (final MapEntry(:key, :value) in containers.entries) {
      next = _withChildren(next, key, value);
    }
    final result = removed == null ? next : next.copyWith(removed: removed);
    _checkRules(layout, result);
    return result;
  }

  /// A patch is held to the rules of a layout, but only for the faults it
  /// adds, so a layout that was already past them can still be edited.
  static void _checkRules(Layout before, Layout after) {
    final added = const LayoutValidator().problemsAdded(
      before: before,
      after: after,
    );
    if (added.isNotEmpty) throw CommandRefused(added.first.message);
  }

  static Map<String, Node> _changedRoots(Layout from, Layout into) {
    final before = {for (final screen in from.screens) screen.id: screen.root};
    return {
      for (final screen in into.screens)
        if (before[screen.id] case final was?
            when !_sameShell(was, screen.root))
          screen.id: _shell(screen.root),
    };
  }

  static Layout _withRoot(Layout layout, String screenId, Node shell) {
    final screen =
        layout.screen(screenId) ?? (throw const CommandRefused(noSuchScreen));
    return layout.copyWith(
      screens: [
        for (final one in layout.screens)
          one.id == screenId
              ? one.withRoot(shell.copyWith(children: screen.root.children))
              : one,
      ],
    );
  }

  static Layout _withChildren(Layout layout, String id, List<Node> wanted) {
    final container =
        layout.node(id) ?? (throw const CommandRefused(layoutGone));
    final current = {for (final child in container.children) child.id: child};
    return layout.withContainer(
      id,
      (container) => container.copyWith(
        children: [
          for (final child in wanted) _holdingNow(child, current[child.id]),
        ],
      ),
    );
  }

  /// [wanted] as it should be, holding what [current] holds now.
  static Node _holdingNow(Node wanted, Node? current) =>
      current == null ? wanted : wanted.copyWith(children: current.children);

  static bool _sameChildren(List<Node> a, List<Node> b) =>
      a.length == b.length &&
      a.indexed.every((entry) => _sameShell(entry.$2, b[entry.$1]));

  static Node _shell(Node node) => node.copyWith(children: const []);

  /// Whether two nodes are alike, not counting what they hold.
  static bool _sameShell(Node a, Node b) =>
      jsonEquals(_shell(a).toJson(), _shell(b).toJson());

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (containers.isNotEmpty)
      'containers': {
        for (final MapEntry(:key, :value) in containers.entries)
          key: [for (final child in value) child.toJson()],
      },
    if (roots.isNotEmpty)
      'roots': {
        for (final MapEntry(:key, :value) in roots.entries) key: value.toJson(),
      },
    if (removed != null) 'removed': removed!.toList()..sort(),
  };
}

/// The commands about nodes, by the name they go by in JSON.
final Map<String, CommandReader> nodeCommandReaders = {
  RemoveNodes.typeName: RemoveNodes.fromJson,
  DropNode.typeName: DropNode.fromJson,
  PatchLayout.typeName: PatchLayout.fromJson,
};
