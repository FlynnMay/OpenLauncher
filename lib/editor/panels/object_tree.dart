import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// A pane's display name: its name, else where it docks.
String paneName(Node pane) {
  // A written name reads variables; it is not one to show.
  final title = pane.name.contains('{{') ? '' : pane.name;
  if (title.isNotEmpty) return title;
  return switch (pane.dock) {
    final dock? => '${barName(dock)} pane',
    null => 'Pane',
  };
}

/// A node's display name: for an instance its own, else its entity's or the
/// node's it is handed, else its prefab's and where it docks; for others
/// their own name, else what they draw.
String objectName(
  Node item,
  Layout? layout,
  List<Entity> entities, {
  Map<String, Prefab> prefabs = const {},
}) {
  if (item.isInstance) {
    if (item.name.isNotEmpty && !item.name.contains('{{')) return item.name;
    final handed = item.handed.firstOrNull;
    if (entities.byId(handed)?.label case final label?) return label;
    if (layout?.node(handed ?? '') case final node? when node.id != item.id) {
      return objectName(node, layout, entities, prefabs: prefabs);
    }
    final name = prefabs[item.prefab]?.name ?? 'Prefab';
    return switch (item.edge) {
      final edge? => '$name · ${barName(edge.name)}',
      null => name,
    };
  }
  if (item.isPane) return paneName(item);
  return item.name.isNotEmpty && !item.name.contains('{{')
      ? item.name
      : item.visual?.label ?? 'Node';
}

IconData objectIcon(Node item) => item.isInstance
    ? prefabIcon
    : !item.isPane
    ? Icons.widgets_outlined
    : item.edge != null
    ? Icons.view_sidebar_outlined
    : item.isDocked
    ? Icons.folder_open_outlined
    : Icons.dashboard_outlined;

/// What is being edited as a tree: each layer and what is on it, or the open
/// prefab's parts by id. Clicking anything selects it; a docked pane is held
/// open on the screen while it or something in it is selected.
class ObjectTree extends ConsumerWidget {
  const ObjectTree({super.key});

  /// Prefix of a layer's node, which is not a component to select.
  static const _layer = 'layer:';

  static Widget _icon(IconData icon) => Icon(icon, size: 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(editedLayoutProvider);
    if (layout == null) return const SizedBox.shrink();
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final selection = ref.watch(selectionProvider);
    final prefab = ref.watch(editedPrefabProvider);
    final prefabs = ref.watch(prefabsProvider);
    // Handed nodes are named from the real layout.
    final real = ref.watch(configProvider).value?.layout;
    final theme = Theme.of(context);

    late List<TreeNode<String>> Function(Node pane) under;
    List<TreeNode<String>> listed(Node pane) => [
      for (final item in pane.children)
        TreeNode(
          id: item.id,
          value: item.id,
          // A prefab's parts go by the id that overrides name them by.
          label: prefab != null
              ? item.id
              : objectName(item, layout, entities, prefabs: prefabs),
          // An instance is marked as one, in colour, and says of what.
          leading: item.isInstance
              ? Tooltip(
                  message:
                      'Prefab: ${prefabs[item.prefab]?.name ?? item.prefab}',
                  child: Icon(
                    prefabIcon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                )
              : _icon(objectIcon(item)),
          trailing: prefab == null
              ? null
              : Text(
                  '${objectName(item, real, entities, prefabs: prefabs)}'
                  '${item.hidden ? ' · hidden' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          children: under(item),
        ),
    ];
    // An instance lists what it holds; a node per slot only with several.
    under = (pane) => pane.isInstance && pane.children.length == 1
        ? listed(pane.children.single)
        : listed(pane);

    if (prefab != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          TreeView<String>.pick(
            nodes: under(layout.home.root),
            picked: selection,
            onPicked: ref.read(selectionProvider.notifier).press,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        TreeView<String>.pick(
          nodes: [
            for (final layer in layout.layers)
              TreeNode(
                id: '$_layer${layer.id}',
                value: '$_layer${layer.id}',
                label: layer.id == Layout.homeId ? 'Home screen' : layer.id,
                leading: _icon(Icons.tv_outlined),
                children: under(layer.root),
              ),
          ],
          // With no selection the launcher's own settings show.
          picked: selection.isEmpty ? {'$_layer${Layout.homeId}'} : selection,
          onPicked: (value) => value.startsWith(_layer)
              ? ref.read(selectionProvider.notifier).clear()
              : ref.read(selectionProvider.notifier).press(value),
        ),
      ],
    );
  }
}
