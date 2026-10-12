import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';

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
              (root) =>
                  root.copyWith(style: withStyle(root.style, {key: value})),
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
        Section('Quick actions', open: false, [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'The menu shown on holding OK: a folder of buttons. Add a '
              'Button from Primitives and give it an action.',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                TvScreen.closePopups();
                TvScreen.openPopup(Layout.menuId);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit menu'),
            ),
          ),
        ]),
        Section('Notifications', open: false, [
          if (ref.watch(tvStateProvider).value?.notificationAccess == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Run "Set up automatically" in the TV\'s Settings to '
                'receive notifications.',
              ),
            ),
          ...optionFields(
            options: ToastOptions.options,
            values: config.toasts.toJson(),
            onChanged: (toasts) => controller.patch({'toasts': toasts}),
          ),
        ]),
      ],
    );
  }
}
