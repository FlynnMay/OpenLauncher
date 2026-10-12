import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// Over the stage while a prefab is open: the way back, the variant shown
/// and what its empty variables are previewed with.
class PrefabBar extends ConsumerWidget {
  const PrefabBar({super.key});

  /// The key standing for "no variants" in the dropdown.
  static const _none = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefab = ref.watch(editedPrefabProvider);
    if (prefab == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final trail = ref.watch(prefabTrailProvider);
    final prefabs = ref.watch(prefabsProvider);
    String named(PrefabMode step) => prefabs[step.id]?.name ?? step.id;
    final mode = trail.lastOrNull;
    final shown = prefab.variantNamed(mode?.variant);
    final byDefault = shown == prefab.defaultVariant;
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final folders = ref.watch(configProvider).value?.layout.docked ?? const [];
    final modified =
        isBuiltIn(prefab.id) &&
        (ref
                .watch(configProvider)
                .value
                ?.prefabs
                .any((own) => own.id == prefab.id) ??
            false);
    final previews = ref.watch(
      runtimeVarsProvider.select((all) => all[prefab.root.id] ?? const {}),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: trail.length < 2
                    ? 'Back to the home screen'
                    : 'Back to ${named(trail[trail.length - 2])}',
                onPressed: () => backPrefab(ref, trail.length - 1),
                icon: const Icon(Icons.arrow_back),
              ),
              TextButton(
                onPressed: () => closePrefab(ref),
                child: const Text('Home screen'),
              ),
              // The prefabs this one was opened through.
              for (final (index, step) in trail.indexed)
                if (index < trail.length - 1) ...[
                  const Icon(Icons.chevron_right, size: 18),
                  TextButton(
                    onPressed: () => backPrefab(ref, index + 1),
                    child: Text(named(step)),
                  ),
                ],
              const Icon(Icons.chevron_right, size: 18),
              const SizedBox(width: 4),
              Text(prefab.name, style: theme.textTheme.titleSmall),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 210,
                child: ChoiceBox<String>(
                  value: shown ?? _none,
                  choices: {
                    if (prefab.variants.isEmpty) _none: 'Default',
                    for (final MapEntry(:key, :value)
                        in prefab.variants.entries)
                      key:
                          '${value.label.isEmpty ? key : value.label}'
                          '${key == prefab.defaultVariant ? ' (default)' : ''}',
                  },
                  onChanged: (key) =>
                      ref.read(prefabTrailProvider.notifier).show(key),
                ),
              ),
              PopupMenuButton<void Function()>(
                tooltip: 'Variants',
                onSelected: (does) => does(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: () => addVariant(context, ref),
                    child: const Text('Add variant'),
                  ),
                  if (shown != null)
                    PopupMenuItem(
                      value: () => renameVariant(context, ref, shown),
                      child: const Text('Rename'),
                    ),
                  // The default is the tree itself and stays.
                  if (shown != null && !byDefault) ...[
                    PopupMenuItem(
                      value: () => makeDefaultVariant(ref, shown),
                      child: const Text('Make default'),
                    ),
                    PopupMenuItem(
                      value: () => deleteVariant(ref, shown),
                      child: const Text('Delete'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          for (final name in previewed(prefab))
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Text('Preview $name with', style: theme.textTheme.bodySmall),
                SizedBox(
                  width: 190,
                  child: SearchBox(
                    value: switch (previews[name]) {
                      final String id => id,
                      _ => null,
                    },
                    hint: 'Nothing',
                    groups: {
                      'Entities': {
                        for (final entity in entities) entity.id: entity.label,
                      },
                      'Folders': {
                        for (final pane in folders)
                          if (pane.hovers && pane.id != Layout.menuId)
                            pane.id: pane.title.isEmpty ? pane.id : pane.title,
                      },
                    },
                    onChanged: (id) => previewWith(ref, name, id),
                  ),
                ),
              ],
            ),
          // A variant made for another shape of cell is seen in one.
          SizedBox(
            width: 250,
            child: NumberField(
              label: 'Cell height',
              value: mode?.height,
              min: Component.minRowHeight.round(),
              max: Component.maxRowHeight.round(),
              step: 4,
              placeholder: 'Auto',
              start: Component.barRowHeight.round(),
              onChanged: (height) => ref
                  .read(prefabTrailProvider.notifier)
                  .drawAt(height.toDouble()),
              onCleared: mode?.height == null
                  ? null
                  : () => ref.read(prefabTrailProvider.notifier).drawAt(null),
            ),
          ),
          if (modified)
            TextButton(
              onPressed: () => deletePrefab(context, ref, prefab),
              child: const Text('Modified · Reset to built-in'),
            ),
        ],
      ),
    );
  }
}
