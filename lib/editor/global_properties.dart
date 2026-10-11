import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/pane_settings.dart';
import 'package:openlauncher/editor/prefab_settings.dart';
import 'package:openlauncher/editor/style_settings.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_screen.dart';
import 'package:openlauncher/editor/values_settings.dart';
import 'package:openlauncher/editor/wallpaper_settings.dart';

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
          sources: config.sources,
          place: config.place,
          onSources: (sources) =>
              controller.change((c) => c.copyWith(sources: sources)),
          onPlace: (place) =>
              controller.change((c) => c.copyWith(place: () => place)),
        ),
        PrefabsSettings(
          prefabs: ref.watch(prefabsProvider),
          own: config.prefabs,
          onChanged: (prefabs) =>
              controller.change((c) => c.copyWith(prefabs: prefabs)),
        ),
        Section('Quick actions', open: false, [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'What holding OK on something offers: a popup of buttons, arranged like '
              'any folder. Buttons for it are under Add.',
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
              label: const Text('Arrange them'),
            ),
          ),
        ]),
        Section('Notifications', open: false, [
          if (ref.watch(tvStateProvider).value?.notificationAccess == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'None are seen until "Set up automatically" has been run in '
                'the TV\'s Settings.',
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
