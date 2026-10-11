import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/dock_settings.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/tree_view.dart';

/// A pane's display name: a sidebar by its edge, a folder or pane by its
/// title.
String paneName(Component pane) {
  if (pane.isDocked && !pane.hovers) return '${barName(pane.dock!)} sidebar';
  // A written title reads variables; it is not a name.
  final title = pane.title.contains('{{') ? '' : pane.title;
  if (title.isNotEmpty) return title;
  if (pane.id == Layout.menuId) return 'Quick actions';
  return pane.isDocked ? 'Folder' : 'Pane';
}

/// A component's display name: its entity's or folder's for an instance, its
/// title for a pane, its label for a button.
String objectName(Component item, Layout? layout, List<Entity> entities) {
  if (item.isInstance) {
    final handed = item.handed.firstOrNull;
    return entities.byId(handed)?.label ??
        switch (layout?.pane(handed ?? '')) {
          null => 'Prefab',
          final folder => paneName(folder),
        };
  }
  if (item.isPane) return paneName(item);
  return switch (item.options['label']) {
    final String label when label.isNotEmpty && !label.contains('{{') => label,
    _ => ComponentRegistry.named(item.kind)?.label ?? 'Component',
  };
}

IconData objectIcon(Component item) => item.isInstance
    ? Icons.crop_16_9
    : !item.isPane
    ? Icons.widgets_outlined
    : !item.isDocked
    ? Icons.dashboard_outlined
    : !item.hovers
    ? Icons.view_sidebar_outlined
    : item.id == Layout.menuId
    ? Icons.more_horiz
    : Icons.folder_open_outlined;

/// The layout as a tree: each layer and what is on it. Clicking anything
/// selects it; a sidebar or folder is held open on the screen while it or
/// something in it is selected.
class ObjectTree extends ConsumerWidget {
  const ObjectTree({super.key});

  /// Prefix of a layer's node, which is not a component to select.
  static const _layer = 'layer:';

  static Widget _icon(IconData icon) => Icon(icon, size: 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(configProvider).value?.layout;
    if (layout == null) return const SizedBox.shrink();
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final selection = ref.watch(selectionProvider);

    List<TreeNode<String>> under(Component pane) => [
      for (final item in pane.children)
        TreeNode(
          id: item.id,
          value: item.id,
          label: objectName(item, layout, entities),
          leading: _icon(objectIcon(item)),
          children: under(item),
        ),
    ];

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
