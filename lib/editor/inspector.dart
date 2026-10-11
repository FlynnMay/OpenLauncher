import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/editor/global_properties.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/object_tree.dart';
import 'package:openlauncher/editor/selected_properties.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/sidebar_settings.dart';

/// The panel of settings beside the screen: those of whatever is picked
/// out on it, or with nothing picked out, those of the launcher as a whole.
class Inspector extends ConsumerWidget {
  const Inspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final found = ref.watch(selectedProvider);
    final bar = ref.watch(barProvider);

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
                child: Text(
                  switch (found.length) {
                    0 => bar == null ? 'Launcher' : '${barName(bar)} sidebar',
                    1 => name(found.single),
                    final count => '$count selected',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (found.isNotEmpty)
                IconButton(
                  tooltip: 'Let go of the selection',
                  onPressed: ref.read(selectionProvider.notifier).clear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Select several'),
          subtitle: const Text('Or hold Ctrl or Shift while clicking'),
          value: ref.watch(selectSeveralProvider),
          onChanged: ref.read(selectSeveralProvider.notifier).set,
        ),
        if (found.isEmpty)
          switch (bar) {
            null => const GlobalProperties(),
            final bar => SidebarSettings(key: ValueKey(bar), id: bar),
          }
        else
          // A new one for each selection, so nothing typed or found for one
          // thing is carried over to the next.
          SelectedProperties(
            key: ValueKey(found.map((one) => one.item.id).join(' ')),
            found: found,
          ),
      ],
    );
  }
}
