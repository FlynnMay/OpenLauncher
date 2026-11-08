import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

/// [item] as the container it resolves to, if that is drawn over the screen:
/// an instance of a docked or Overlay prefab is drawn like one.
Node? dockedForm(Node item, Map<String, Prefab> prefabs) {
  if (!item.isInstance) return null;
  final container = resolved(item, prefabs);
  return container.offCells ? container : null;
}

/// [layout] with its instances of docked and Overlay containers resolved.
Layout withDockedInstances(Layout layout, Map<String, Prefab> prefabs) =>
    layout.rebuild(
      (_, items) => [
        for (final item in items) dockedForm(item, prefabs) ?? item,
      ],
    );
