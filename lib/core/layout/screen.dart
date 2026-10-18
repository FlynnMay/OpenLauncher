import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// One screen: a tree of nodes under [root], which fills it.
@immutable
class Screen {
  const Screen({required this.id, required this.root});

  /// A screen with an empty root container.
  Screen.empty(this.id) : root = _emptyRoot(id);

  final String id;

  final Node root;

  static String rootId(String screenId) => '$screenId/root';

  static Node _emptyRoot(String id) => Node.layout(
    id: rootId(id),
    mode: LayoutMode.grid,
    columns: LayoutModule.globalColumns,
  );

  Screen withRoot(Node root) => Screen(id: id, root: root);

  factory Screen.fromJson(Map<Object?, Object?> json) {
    final id = jsonRequired<String>(json, 'id');
    return Screen(
      id: id,
      root: switch (jsonOptional<Map<Object?, Object?>>(json, 'root')) {
        final container? => Node.fromJson(container),
        null => _emptyRoot(id),
      },
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'root': root.toJson()};
}
