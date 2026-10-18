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

  /// The node [reference] names on this screen: one of that id, else this
  /// screen's own copy of it (see [copied]). A prefab can name a node of the
  /// screen it is on without knowing which screen that is.
  Node? find(String reference) {
    Node? copy;
    for (final node in root.all) {
      if (node.id == reference) return node;
      if (node.id == '$id/$reference') copy = node;
    }
    return copy;
  }

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

/// Which screen the launcher opens on: [screen], or the one shown last if it
/// should [remember] and there is one.
@immutable
class Startup {
  const Startup(this.screen, {this.remember = false});

  final String screen;
  final bool remember;

  factory Startup.fromJson(Object? json) => switch (json) {
    {'screen': final String screen} => Startup(
      screen,
      remember: json['remember'] == true,
    ),
    _ => const Startup(''),
  };

  Map<String, Object?> toJson() => {
    'screen': screen,
    if (remember) 'remember': true,
  };

  @override
  bool operator ==(Object other) =>
      other is Startup && other.screen == screen && other.remember == remember;

  @override
  int get hashCode => Object.hash(screen, remember);
}
