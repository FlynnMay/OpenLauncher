import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// Launcher-wide settings, shown when nothing is selected.
class GlobalProperties extends ConsumerWidget {
  const GlobalProperties({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final controller = ref.read(configProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WallpaperSettings(),
        if (config.ownLayout) const _RevertLayout(),
        // The screen's root pane.
        PaneSettings(
          title: 'Screen',
          prefabs: ref.watch(prefabsProvider),
          named: false,
          dockable: false,
          panes: [config.layout.home.root],
          onChanged: (how) => changeLayout(
            context,
            ref,
            (layout) => layout.withPane(layout.home.root.id, how),
          ),
        ),
        StyleSettings(
          keys: const ['padding', ...textStyle],
          style: config.layout.home.root.style,
          onChanged: (key, value) => changeLayout(
            context,
            ref,
            (layout) => layout.withPane(
              layout.home.root.id,
              (root) => root.styled(withStyle(root.style, {key: value})),
            ),
          ),
        ),
        ValuesSettings(
          entities: config.entities,
          place: config.place,
          onEntities: (entities) =>
              controller.change((c) => c.copyWith(entities: entities)),
          onPlace: (place) =>
              controller.change((c) => c.copyWith(place: () => place)),
        ),
        const PrefabList(),
        Section('Notifications', open: false, [
          const AccessNote(Access.notifications),
          ...optionFields(
            options: ToastOptions.options,
            values: config.toasts.toJson(),
            onChanged: (toasts) => controller.patch({'toasts': toasts}),
          ),
        ]),
        const UpdateSettings(),
        const DevicesSettings(),
      ],
    );
  }
}

/// Puts back the home screen its pack starts with.
class _RevertLayout extends ConsumerWidget {
  const _RevertLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(
      packNameProvider(ref.watch(startingLayoutProvider).value?.id ?? ''),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () async {
          if (!await confirm(
            context,
            'Revert the screen to $pack?',
            'Every layer goes back to how $pack starts it. Your changes to '
                'the layout are lost; Undo brings them back.',
            'Revert',
          )) {
            return;
          }
          ref.read(selectionProvider.notifier).clear();
          await ref.read(configProvider.notifier).revertLayout();
        },
        child: Text('Screen modified · Revert to $pack'),
      ),
    );
  }
}
