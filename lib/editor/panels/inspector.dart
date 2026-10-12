import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/panels/global_properties.dart';
import 'package:openlauncher/editor/panels/object_tree.dart';
import 'package:openlauncher/editor/panels/selected_properties.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// The settings panel: the selection's, or with nothing selected the
/// launcher's, or the open prefab's and its root's.
class Inspector extends ConsumerWidget {
  const Inspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final found = ref.watch(selectedProvider);
    final prefab = ref.watch(editedPrefabProvider);
    final layout = ref.watch(editedLayoutProvider);

    String name(Found one) => prefab != null
        ? one.item.id
        : objectName(
            one.item,
            ref.watch(configProvider).value?.layout,
            ref.watch(entitiesProvider).value ?? const [],
            prefabs: ref.watch(prefabsProvider),
          );

    return ListView(
      // From the top again when a prefab is opened or closed.
      key: ValueKey('inspector ${prefab?.id}'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        switch (found.length) {
                          0 => prefab?.name ?? 'Launcher',
                          1 => name(found.single),
                          final count => '$count selected',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // What templates and actions name it by.
                    if (found.length == 1 && prefab == null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: IdLabel(found.single.item.id)),
                    ],
                    if (found.isEmpty && prefab != null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: IdLabel(prefab.id)),
                    ],
                  ],
                ),
              ),
              // A part's id is its name; overrides go by it.
              if (found.length == 1 && prefab != null)
                IconButton(
                  tooltip: 'Rename',
                  onPressed: () => renamePart(context, ref, found.single.item),
                  icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                ),
              if (found.isNotEmpty)
                IconButton(
                  tooltip: 'Deselect',
                  onPressed: ref.read(selectionProvider.notifier).clear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Multi-select'),
          subtitle: const Text('Or hold Ctrl or Shift while clicking'),
          value: ref.watch(selectSeveralProvider),
          onChanged: ref.read(selectSeveralProvider.notifier).set,
        ),
        if (found.isEmpty && prefab == null)
          const GlobalProperties()
        else if (found.isEmpty) ...[
          PrefabDetails(prefab: prefab!),
          // The root is the prefab: its variables, actions, style and size.
          if (layout == null ? null : findItems(layout, {prefab.root.id})
              case final root? when root.isNotEmpty)
            SelectedProperties(
              key: ValueKey('root of ${prefab.id}'),
              found: root,
            ),
        ] else
          // Keyed by selection so no field state carries over.
          SelectedProperties(
            key: ValueKey(found.map((one) => one.item.id).join(' ')),
            found: found,
          ),
      ],
    );
  }
}
