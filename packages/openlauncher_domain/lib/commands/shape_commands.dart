import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/node_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

const _nothingThere = 'There is nothing there to change.';

/// Docks an instance of [prefab] to [edge], if nothing is docked there.
class DockPrefab extends NodeEdit {
  const DockPrefab(this.edge, this.prefab);

  factory DockPrefab.fromJson(Json json) => DockPrefab(
    jsonRequired<String>(json, 'edge'),
    Prefab.fromJson(json['prefab']) ??
        (throw const FormatException('"prefab"')),
  );

  static const typeName = 'node.dock';

  final String edge;
  final Prefab prefab;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (dockedOn(layout, edge) != null) {
      throw const CommandRefused('That edge has something docked already.');
    }
    return withDocked(layout, edge, prefab);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'edge': edge,
    'prefab': prefab.toJson(),
  };
}

/// Makes a container the one that new entities arrive in.
class SetInbox extends NodeEdit {
  const SetInbox(this.containerId);

  factory SetInbox.fromJson(Json json) =>
      SetInbox(jsonRequired<String>(json, 'container'));

  static const typeName = 'layout.inbox';

  final String containerId;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) => layout.node(containerId) == null
      ? throw const CommandRefused(_nothingThere)
      : withInbox(layout, containerId);

  @override
  Map<String, Object?> toJson() => {'type': type, 'container': containerId};
}

/// The commands that shape nodes, by the name they go by in JSON.
final Map<String, CommandReader> shapeCommandReaders = {
  DockPrefab.typeName: DockPrefab.fromJson,
  SetInbox.typeName: SetInbox.fromJson,
};
