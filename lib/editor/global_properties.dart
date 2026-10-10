import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/order_list.dart';
import 'package:openlauncher/editor/pane_settings.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/wallpaper_settings.dart';

/// What is set for the launcher as a whole, shown while nothing on the
/// screen is picked out: the wallpaper, how the screen itself arranges
/// things, the menu a held card opens, and notifications.
class GlobalProperties extends ConsumerWidget {
  const GlobalProperties({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final controller = ref.read(configProvider.notifier);
    final toasts = config.toasts;
    ToastOptions toast({
      bool? enabled,
      ToastPosition? position,
      int? seconds,
    }) => ToastOptions(
      enabled: enabled ?? toasts.enabled,
      position: position ?? toasts.position,
      seconds: seconds ?? toasts.seconds,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WallpaperSettings(),
        // The screen is a pane like any other, only without a name.
        PaneSettings(
          title: 'Screen',
          named: false,
          panes: [config.layout.home.root],
          onChanged: (how) => changeLayout(
            context,
            ref,
            (layout) => changePanel(
              layout,
              Layout.homeId,
              (panel) => panel.withRoot(how(panel.root)),
            ),
          ),
        ),
        Section('Menu on holding OK', [
          OrderList<CardAction>(
            all: CardAction.values,
            chosen: config.contextMenu,
            label: (action) => action.label,
            onChanged: controller.setContextMenu,
          ),
        ]),
        Section('Notifications', [
          if (ref.watch(tvStateProvider).value?.notificationAccess == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'None are seen until "Set up automatically" has been run in '
                'the TV\'s Settings.',
              ),
            ),
          TickBox(
            label: 'Pop up over the home screen',
            value: toasts.enabled,
            onChanged: (on) => controller.setToasts(toast(enabled: on)),
          ),
          LabelledRow(
            'Corner',
            ChoiceBox<ToastPosition>(
              value: toasts.position,
              choices: const {
                ToastPosition.topLeft: 'Top left',
                ToastPosition.topRight: 'Top right',
                ToastPosition.bottomLeft: 'Bottom left',
                ToastPosition.bottomRight: 'Bottom right',
              },
              onChanged: (position) =>
                  controller.setToasts(toast(position: position)),
            ),
          ),
          NumberStepper(
            label: 'Seconds',
            value: toasts.seconds * 1.0,
            min: 2,
            max: 30,
            onChanged: (seconds) =>
                controller.setToasts(toast(seconds: seconds)),
          ),
        ]),
      ],
    );
  }
}
