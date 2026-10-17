import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// Display name of a dock.
String barName(String dock) => switch (dock) {
  'left' => 'Left',
  'right' => 'Right',
  'top' => 'Top',
  'bottom' => 'Bottom',
  'center' => 'Centre',
  _ => dock,
};

/// A size that is automatic, fill, or a number of TV pixels.
class ExtentBox extends StatelessWidget {
  const ExtentBox({
    super.key,
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  final String label;

  /// Null for default, [DockModule.fill] for fill.
  final double? value;

  /// The default, used as the starting number; null if it is as big as what
  /// is in it.
  final double? defaultValue;
  final void Function(double? value) onChanged;

  static const _auto = 'auto', _fill = 'fill', _fixed = 'fixed';

  @override
  Widget build(BuildContext context) {
    final value = this.value, byDefault = defaultValue;
    final numbered = value != null && value != DockModule.fill;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabelledRow(
          label,
          ChoiceBox<String>(
            value: value == null
                ? _auto
                : numbered
                ? _fixed
                : _fill,
            choices: {
              _auto: switch (byDefault) {
                null => 'Auto (fit content)',
                DockModule.fill => 'Auto (fill)',
                _ => 'Auto (${byDefault.round()})',
              },
              _fill: 'Fill',
              _fixed: 'Fixed',
            },
            onChanged: (choice) => onChanged(switch (choice) {
              _fill => DockModule.fill,
              _fixed =>
                byDefault == null || byDefault == DockModule.fill
                    ? 300
                    : byDefault,
              _ => null,
            }),
          ),
        ),
        if (numbered)
          NumberField(
            label: '',
            value: value,
            min: 40,
            max: DockModule.maxExtent.round(),
            step: 10,
            onChanged: (size) => onChanged(size * 1.0),
          ),
      ],
    );
  }
}

/// Where a pane is docked and, once it is, its size and how it opens.
List<Widget> dockFields(
  Node pane,
  void Function(Node Function(Node pane) how) change,
) {
  // The dock's defaults.
  final defaults = Node.layout(id: '', dock: {'position': ?pane.dock});
  final values = pane.values(dockModule.name) ?? const {};
  final [dock, ...rest] = [
    for (final field in dockModule.fields)
      if (field.when?.call(values) ?? true) field,
  ];
  List<Widget> fields(List<Field> options) => ruleFields(
    options: options,
    json: values,
    onChanged: (key, value) =>
        change((pane) => withRule(pane, dockModule.name, key, value)),
  );
  return [
    ...fields([dock]),
    if (pane.isDocked) ...[
      ExtentBox(
        label: 'Width',
        value: pane.dockWidth,
        defaultValue: defaults.openWidth,
        onChanged: (width) =>
            change((pane) => withRule(pane, dockModule.name, 'width', width)),
      ),
      ExtentBox(
        label: 'Height',
        value: pane.dockHeight,
        defaultValue: defaults.openHeight,
        onChanged: (height) =>
            change((pane) => withRule(pane, dockModule.name, 'height', height)),
      ),
    ],
    ...fields(rest),
    if (pane.isDocked) const _Replay(),
  ];
}

/// Lets go of the selected docked pane for a moment, so it closes and opens.
class _Replay extends ConsumerWidget {
  const _Replay();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: ref.watch(barReplayProvider)
          ? null
          : () => ref.read(barReplayProvider.notifier).play(),
      icon: const Icon(Icons.play_arrow),
      label: const Text('Preview animation'),
    ),
  );
}
