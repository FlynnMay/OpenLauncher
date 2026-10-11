import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/sidebar_settings.dart';
import 'package:openlauncher/editor/tree_view.dart';
import 'package:openlauncher/editor/tv_screen.dart';

/// What [item] is called: an instance by the name of the entity it was
/// handed, or of the folder it opens; a pane by its title; a button by
/// what it says, where that is plain to read.
String objectName(Component item, Layout? layout, List<Entity> entities) {
  if (item.isInstance) {
    final handed = item.handed.firstOrNull;
    return entities.byId(handed)?.label ??
        switch (layout?.panel(handed ?? '')?.title) {
          null => 'Prefab',
          '' => 'Folder',
          final title => title,
        };
  }
  if (item.isPane) return item.title.isEmpty ? 'Pane' : item.title;
  return switch (item.options['label']) {
    final String label when label.isNotEmpty && !label.contains('{{') => label,
    _ => ComponentKind.named(item.kind)?.label ?? 'Component',
  };
}

IconData objectIcon(Component item) => item.isInstance
    ? Icons.crop_16_9
    : item.isPane
    ? Icons.dashboard_outlined
    : Icons.widgets_outlined;

/// Everything on the TV as a tree: the home screen, each sidebar and each
/// folder, and under them the panes, entities and components as they are nested.
/// A press picks a thing out, as a press on it on the screen does; a press
/// on a sidebar or a folder brings it up on the screen.
class ObjectTree extends ConsumerWidget {
  const ObjectTree({super.key});

  /// In front of a panel's id, to tell it from the id of an item.
  static const _panel = 'panel:';

  static Widget _icon(IconData icon) => Icon(icon, size: 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(configProvider).value?.layout;
    if (layout == null) return const SizedBox.shrink();
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final selection = ref.watch(selectionProvider);
    final bar = ref.watch(barProvider);

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
    TreeNode<String> panel(Panel panel, String label, IconData icon) =>
        TreeNode(
          id: '$_panel${panel.id}',
          value: '$_panel${panel.id}',
          label: label,
          leading: _icon(icon),
          children: under(panel.root),
        );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        TreeView<String>.pick(
          nodes: [
            panel(layout.home, 'Home screen', Icons.tv_outlined),
            for (final id in Layout.barIds)
              if (layout.panel(id) case final sidebar?
                  when sidebar.root.children.isNotEmpty || id == bar)
                panel(
                  sidebar,
                  '${barName(id)} sidebar',
                  Icons.view_sidebar_outlined,
                ),
            for (final popup in layout.panels)
              if (popup.kind == PanelKind.popup)
                panel(
                  popup,
                  popup.title.isNotEmpty
                      ? popup.title
                      : popup.id == Layout.menuId
                      ? 'Quick actions'
                      : 'Folder',
                  popup.id == Layout.menuId
                      ? Icons.more_horiz
                      : Icons.folder_open_outlined,
                ),
          ],
          // With nothing picked out, what the settings beside the screen
          // are those of.
          picked: selection.isEmpty
              ? {'$_panel${bar ?? Layout.homeId}'}
              : selection,
          onPicked: (value) {
            if (!value.startsWith(_panel)) {
              return ref.read(selectionProvider.notifier).press(value);
            }
            final id = value.substring(_panel.length);
            final kind = Panel.kindOf(id);
            ref.read(selectionProvider.notifier).clear();
            ref
                .read(barProvider.notifier)
                .set(kind == PanelKind.sidebar ? id : null);
            TvScreen.closePopups();
            if (kind == PanelKind.popup) TvScreen.openPopup(id);
          },
        ),
      ],
    );
  }
}
