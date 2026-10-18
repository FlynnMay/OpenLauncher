import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// A container's display name: its name, else where it docks.
String containerName(Node container) {
  // A written name reads variables; it is not one to show.
  final title = container.name.contains('{{') ? '' : container.name;
  if (title.isNotEmpty) return title;
  return switch (container.dock) {
    final dock? => '${barName(dock)} dock',
    null when container.has(layoutModule.name) => 'Layout',
    null => 'Empty',
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
  if (item.isContainer) return containerName(item);
  return item.name.isNotEmpty && !item.name.contains('{{')
      ? item.name
      : item.visual?.label ?? 'Node';
}

IconData objectIcon(Node item) => item.isInstance
    ? prefabIcon
    : !item.isContainer
    ? Icons.widgets_outlined
    : item.edge != null
    ? Icons.view_sidebar_outlined
    : item.isDocked
    ? Icons.folder_open_outlined
    : item.isOverlay
    ? Icons.layers_outlined
    : Icons.dashboard_outlined;

/// What is being edited as a tree: each screen and what is on it, or the open
/// prefab's parts by id. Clicking anything selects it; a docked container is
/// held open on the screen while it or something in it is selected.
class ObjectTree extends ConsumerWidget {
  const ObjectTree({super.key});

  /// Prefix of a screen's row, which is not a component to select.
  static const _screen = 'screen:';
  static const _launcher = 'launcher:', _screens = 'screens:';

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

    late List<TreeNode<String>> Function(Node container) under;
    List<TreeNode<String>> listed(Node container) => [
      for (final item in container.children)
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
    under = (container) =>
        container.isInstance && container.children.length == 1
        ? listed(container.children.single)
        : listed(container);

    if (prefab != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          TreeView<String>.pick(
            nodes: under(layout.start.root),
            picked: selection,
            onPicked: ref.read(selectionProvider.notifier).press,
          ),
        ],
      );
    }

    final shown = ref.watch(currentScreenProvider)?.id;
    final startup = real?.startup;
    final launcher = ref.watch(inspectLauncherProvider);
    final nothing = selection.isEmpty;

    void showScreen(String id) {
      if (id != shown) ref.read(shownScreensProvider.notifier).open(id);
    }

    String screenName(Screen screen) => screen.root.name.isNotEmpty
        ? screen.root.name
        : screen.id.split(':').last;

    Widget screenMenu(Screen screen) => PopupMenuButton<String>(
      tooltip: 'Screen',
      iconSize: 18,
      padding: EdgeInsets.zero,
      onSelected: (choice) async {
        switch (choice) {
          case 'rename':
            final name = await askName(
              context,
              screen.root.name,
              title: 'Screen name',
              does: 'Rename',
            );
            if (name != null && context.mounted) {
              await runLauncher(context, ref, 'launcher://screen/rename', {
                'id': screen.id,
                'name': name,
              });
            }
          case 'duplicate':
            await runLauncher(context, ref, 'launcher://screen/duplicate', {
              'id': screen.id,
            });
          case 'startup':
            await runLauncher(context, ref, 'launcher://screen/startup', {
              'id': screen.id,
              'remember': startup?.remember ?? false,
            });
          case 'remove':
            if (await confirm(
                  context,
                  'Delete ${screenName(screen)}?',
                  'The screen and everything on it go; Undo brings them back.',
                  'Delete',
                ) &&
                context.mounted) {
              await runLauncher(context, ref, 'launcher://screen/remove', {
                'id': screen.id,
              });
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'startup', child: Text('Set as startup')),
        const PopupMenuItem(value: 'remove', child: Text('Delete')),
      ],
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        TreeView<String>.pick(
          nodes: [
            TreeNode(
              id: _launcher,
              value: _launcher,
              label: 'Launcher',
              leading: _icon(Icons.settings_outlined),
            ),
            TreeNode(
              id: _screens,
              label: 'Screens',
              leading: _icon(Icons.collections_outlined),
              trailing: IconButton(
                tooltip: 'Add a screen',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => runLauncher(
                  context,
                  ref,
                  'launcher://screen/add',
                  {'name': 'Screen ${layout.screens.length + 1}'},
                ),
                icon: const Icon(Icons.add),
              ),
              children: [
                for (final screen in layout.screens)
                  TreeNode(
                    id: '$_screen${screen.id}',
                    value: '$_screen${screen.id}',
                    label: screenName(screen),
                    // A dot marks the screen on the stage, a star the startup.
                    leading: _icon(
                      screen.id == startup?.screen
                          ? Icons.star
                          : screen.id == shown
                          ? Icons.circle
                          : Icons.circle_outlined,
                    ),
                    trailing: screenMenu(screen),
                    children: under(screen.root),
                  ),
              ],
            ),
          ],
          picked: {
            ...selection,
            if (nothing && launcher) _launcher,
            if (nothing && !launcher && shown != null) '$_screen$shown',
          },
          onPicked: (value) {
            final inspect = ref.read(inspectLauncherProvider.notifier);
            if (value == _launcher) {
              inspect.set(true);
              ref.read(selectionProvider.notifier).clear();
            } else if (value.startsWith(_screen)) {
              inspect.set(false);
              showScreen(value.substring(_screen.length));
              ref.read(selectionProvider.notifier).clear();
            } else {
              // A node of another screen brings that screen up.
              for (final screen in layout.screens) {
                if (screen.root.all.any((node) => node.id == value)) {
                  showScreen(screen.id);
                }
              }
              ref.read(selectionProvider.notifier).press(value);
            }
          },
        ),
      ],
    );
  }
}
