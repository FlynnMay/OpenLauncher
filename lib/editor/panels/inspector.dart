import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/panels/global_properties.dart';
import 'package:openlauncher/editor/panels/object_tree.dart';
import 'package:openlauncher/editor/panels/selected_properties.dart';

/// The settings panel: the selection's, or the launcher's when nothing is
/// selected.
class Inspector extends ConsumerWidget {
  const Inspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final found = ref.watch(selectedProvider);

    String name(Found one) => objectName(
      one.item,
      ref.watch(configProvider).value?.layout,
      ref.watch(entitiesProvider).value ?? const [],
    );

    return ListView(
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
                          0 => 'Launcher',
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
                    if (found.length == 1) ...[
                      const SizedBox(width: 8),
                      Flexible(child: IdLabel(found.single.item.id)),
                    ],
                  ],
                ),
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
        if (found.isEmpty)
          const GlobalProperties()
        else
          // Keyed by selection so no field state carries over.
          SelectedProperties(
            key: ValueKey(found.map((one) => one.item.id).join(' ')),
            found: found,
          ),
      ],
    );
  }
}
