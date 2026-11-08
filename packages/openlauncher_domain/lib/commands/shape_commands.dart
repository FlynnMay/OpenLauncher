import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/node_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/nodes/geometry.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

const _nothingThere = 'There is nothing there to change.';

Layout _requiring(Layout layout, String id) => layout.node(id) == null
    ? throw const CommandRefused(_nothingThere)
    : layout;

/// Resizes and repositions a node of a grid or flow container. Whatever is in
/// the way moves aside.
class ReshapeNode extends NodeEdit {
  const ReshapeNode(
    this.id, {
    required this.w,
    required this.h,
    this.x,
    this.y,
  });

  factory ReshapeNode.fromJson(Json json) => ReshapeNode(
    jsonRequired<String>(json, 'id'),
    w: jsonRequired<num>(json, 'w').toDouble(),
    h: jsonRequired<num>(json, 'h').toDouble(),
    x: jsonOptional<num>(json, 'x')?.toDouble(),
    y: jsonOptional<num>(json, 'y')?.toDouble(),
  );

  static const typeName = 'node.reshape';

  final String id;
  final double w, h;
  final double? x, y;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) =>
      reshapeItem(_requiring(layout, id), id, w: w, h: h, x: x, y: y);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'w': w,
    'h': h,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };
}

/// Moves a node of a free container to cover [rect] of it, which is [extent]
/// big.
class PlaceNode extends NodeEdit {
  const PlaceNode(this.id, this.rect, this.extent);

  factory PlaceNode.fromJson(Json json) => PlaceNode(
    jsonRequired<String>(json, 'id'),
    Box.fromJson(json['rect']) ?? (throw const FormatException('"rect"')),
    Extent.fromJson(json['extent']) ??
        (throw const FormatException('"extent"')),
  );

  static const typeName = 'node.place';

  final String id;
  final Box rect;
  final Extent extent;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) =>
      placeItem(_requiring(layout, id), id, rect, extent);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'rect': rect.toJson(),
    'extent': extent.toJson(),
  };
}

/// Sets one Sizing field (`w`, `h`, `x`, `y`, `flex`, `aspect`) on nodes; null
/// clears it.
class SetSizing extends NodeEdit {
  const SetSizing(this.ids, this.key, this.value);

  factory SetSizing.fromJson(Json json) => SetSizing(
    {for (final id in jsonRequired<List<Object?>>(json, 'ids')) id! as String},
    jsonRequired<String>(json, 'key'),
    jsonOptional<num>(json, 'value')?.toDouble(),
  );

  static const typeName = 'node.sizing';

  final Set<String> ids;
  final String key;
  final double? value;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (!ids.any((id) => layout.node(id) != null)) {
      throw const CommandRefused(_nothingThere);
    }
    return transformItems(layout, ids, key, value);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'ids': ids.toList()..sort(),
    'key': key,
    if (value != null) 'value': value,
  };
}

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
  Layout apply(Layout layout) =>
      withInbox(_requiring(layout, containerId), containerId);

  @override
  Map<String, Object?> toJson() => {'type': type, 'container': containerId};
}

/// The commands that shape nodes, by the name they go by in JSON.
final Map<String, CommandReader> shapeCommandReaders = {
  ReshapeNode.typeName: ReshapeNode.fromJson,
  PlaceNode.typeName: PlaceNode.fromJson,
  SetSizing.typeName: SetSizing.fromJson,
  DockPrefab.typeName: DockPrefab.fromJson,
  SetInbox.typeName: SetInbox.fromJson,
};
