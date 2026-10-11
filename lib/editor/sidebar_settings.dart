import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/pane_settings.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/style_settings.dart';

/// What the sidebar on the edge [id] names is called.
String barName(String id) => switch (Panel.edgeOf(id)) {
  BarEdge.left => 'Left',
  BarEdge.right => 'Right',
  BarEdge.top => 'Top',
  BarEdge.bottom => 'Bottom',
  null => id,
};

/// A length that is either the usual one, all there is, or a number of the
/// TV's pixels: how a sidebar's width and height are set.
class ExtentBox extends StatelessWidget {
  const ExtentBox({
    super.key,
    required this.label,
    required this.value,
    required this.usual,
    required this.onChanged,
  });

  final String label;

  /// Null for the usual, [Panel.fill] for all there is, else the number.
  final double? value;

  /// What the usual one comes to, to start from when a number is asked for.
  final double usual;
  final void Function(double? value) onChanged;

  static const _usual = 'usual', _fill = 'fill', _set = 'set';

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final numbered = value != null && value != Panel.fill;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabelledRow(
          label,
          ChoiceBox<String>(
            value: value == null
                ? _usual
                : numbered
                ? _set
                : _fill,
            choices: {
              _usual: usual == Panel.fill
                  ? 'Usual (fills)'
                  : 'Usual (${usual.round()})',
              _fill: 'Fills the screen',
              _set: 'Set',
            },
            onChanged: (choice) => onChanged(switch (choice) {
              _fill => Panel.fill,
              _set => usual == Panel.fill ? 300 : usual,
              _ => null,
            }),
          ),
        ),
        if (numbered)
          NumberStepper(
            label: '',
            value: value,
            min: 40,
            max: Panel.maxExtent.round(),
            step: 10,
            onChanged: (size) => onChanged(size * 1.0),
          ),
      ],
    );
  }
}

Future<bool> _sure(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the sidebar?'),
        content: const Text(
          'What is in it comes off the TV with it. The apps can be added '
          'again anywhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ??
    false;

/// The settings of one sidebar: how big it is open and closed, and, since
/// inside it is a pane like any other, everything a pane has.
class SidebarSettings extends ConsumerWidget {
  const SidebarSettings({super.key, required this.id});

  /// The panel id of the sidebar, which is also the edge it is on.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(configProvider).value?.layout.panel(id);
    if (panel == null) return const SizedBox.shrink();
    void change(Panel Function(Panel panel) how) =>
        changeLayout(context, ref, (layout) => changePanel(layout, id, how));
    void pane(Pane Function(Pane pane) how) =>
        change((panel) => panel.withRoot(how(panel.root)));
    // What the edge would give, were nothing set.
    final usual = Panel.empty(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              const Text(
                'It stays open here while you arrange it. Drag things into '
                'it from the left, or from the screen.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ref.read(barProvider.notifier).set(null),
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      // Emptied, it is simply gone; with things in it, they
                      // come off the TV with it.
                      if (panel.items.isNotEmpty && !await _sure(context)) {
                        return;
                      }
                      if (!context.mounted) return;
                      ref.read(selectionProvider.notifier).clear();
                      ref.read(barProvider.notifier).set(null);
                      await changeLayout(
                        context,
                        ref,
                        (layout) => removePanel(layout, id),
                      );
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove the sidebar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Section('Size', [
          ExtentBox(
            label: 'Width',
            value: panel.width,
            usual: usual.openWidth,
            onChanged: (width) =>
                change((panel) => panel.copyWith(width: width)),
          ),
          ExtentBox(
            label: 'Height',
            value: panel.height,
            usual: usual.openHeight,
            onChanged: (height) =>
                change((panel) => panel.copyWith(height: height)),
          ),
          // Its rules as a pane that is shown and hidden.
          ...ruleFields(
            options: panelRules(panel),
            json: panel.toJson(),
            onChanged: (key, value) =>
                change((panel) => withPanelRule(panel, key, value)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: ref.watch(barReplayProvider)
                  ? null
                  : () => ref.read(barReplayProvider.notifier).play(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Show it opening'),
            ),
          ),
        ]),
        PaneSettings(
          title: 'Its pane',
          prefabs: ref.watch(prefabsProvider),
          usualOn: usualPanelTriggers(panel),
          panes: [panel.root],
          onChanged: pane,
        ),
        StyleSettings(
          keys: const [...boxStyle, ...textStyle],
          style: panel.root.style,
          corner: Pane.defaultCorner,
          onChanged: (key, value) => pane(
            (pane) => pane.copyWith(style: withStyle(pane.style, {key: value})),
          ),
        ),
      ],
    );
  }
}
