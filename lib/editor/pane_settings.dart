import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/corner_settings.dart';
import 'package:openlauncher/editor/layout_edit.dart';

/// How one or more panes arrange what is in them: the same settings for a
/// pane on the screen and for the screen itself, which is a pane too.
class PaneSettings extends StatelessWidget {
  const PaneSettings({
    super.key,
    required this.title,
    required this.panes,
    required this.onChanged,
    this.named = true,
    this.shaped = true,
    this.children = const [],
  });

  /// The heading the settings go under.
  final String title;
  final List<Pane> panes;

  /// Called with how each of the panes is to change.
  final void Function(Pane Function(Pane pane) change) onChanged;

  /// Whether a pane's own title is among its settings.
  final bool named;

  /// Whether the roundness of a pane's corners is among its settings; the
  /// screen has none to round.
  final bool shaped;

  /// More settings, shown after these.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Section(title, [
    if (named && panes.length == 1)
      CommitField(
        label: 'Title',
        value: panes.single.title,
        onChanged: (title) => onChanged((pane) => pane.copyWith(title: title)),
      ),
    LabelledRow(
      'Placement',
      ChoiceBox<PaneMode>(
        value: shared(panes.map((pane) => pane.mode)),
        choices: const {
          PaneMode.flow: 'In order',
          PaneMode.grid: 'On cells',
          PaneMode.free: 'Anywhere',
        },
        onChanged: (mode) => onChanged((pane) => withMode(pane, mode)),
      ),
    ),
    NumberStepper(
      label: 'Columns',
      value: shared(panes.map((pane) => pane.columns * 1.0)),
      min: 1,
      max: Pane.maxColumns,
      onChanged: (columns) => onChanged((pane) => withColumns(pane, columns)),
    ),
    NumberStepper(
      label: 'Spacing',
      value: shared(panes.map((pane) => pane.spacing ?? -1)),
      usual: 'Usual',
      min: 0,
      max: Pane.maxSpacing.round(),
      step: 2,
      onChanged: (spacing) => onChanged(
        (pane) => pane.copyWith(spacing: spacing < 0 ? null : spacing * 1.0),
      ),
    ),
    NumberStepper(
      label: 'Padding',
      value: shared(panes.map((pane) => pane.padding ?? -1)),
      usual: 'Usual',
      min: 0,
      max: Pane.maxPadding.round(),
      step: 2,
      onChanged: (padding) => onChanged(
        (pane) => pane.copyWith(padding: padding < 0 ? null : padding * 1.0),
      ),
    ),
    NumberStepper(
      label: 'Row height',
      value: shared(panes.map((pane) => pane.rowHeight ?? -1)),
      usual: 'By shape',
      min: Pane.minRowHeight.round(),
      max: Pane.maxRowHeight.round(),
      step: 4,
      onChanged: (height) => onChanged(
        (pane) => pane.copyWith(
          rowHeight: height < Pane.minRowHeight ? null : height * 1.0,
        ),
      ),
    ),
    if (shaped)
      CornerSettings(
        corners: panes.first.corners,
        usual: Pane.defaultCorner,
        max: Pane.maxCorner,
        onChanged: (corners) =>
            onChanged((pane) => pane.copyWith(corners: corners)),
      ),
    ...children,
    const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 4),
      child: Text('For every card in it'),
    ),
    LabelledRow(
      'Drawn',
      ChoiceBox<String>(
        value: shared(panes.map((pane) => pane.itemLook?.name ?? _each)),
        choices: const {
          _each: 'As each card says',
          'card': 'Name under the picture',
          'row': 'Name beside the picture',
        },
        onChanged: (look) => onChanged(
          (pane) => pane.copyWith(itemLook: TileLook.values.asNameMap()[look]),
        ),
      ),
    ),
    LabelledRow(
      'Name',
      ChoiceBox<String>(
        value: shared(panes.map((pane) => pane.itemNames?.toString() ?? _each)),
        choices: const {
          _each: 'As each card says',
          'true': 'Shown',
          'false': 'Hidden',
        },
        onChanged: (names) => onChanged(
          (pane) => pane.copyWith(
            itemNames: switch (names) {
              'true' => true,
              'false' => false,
              _ => null,
            },
          ),
        ),
      ),
    ),
    TickBox(
      label: 'All the same size',
      value: shared(panes.map((pane) => pane.itemW != null)),
      onChanged: (same) => onChanged(
        (pane) => pane.copyWith(
          itemW: same ? pane.itemW ?? 1.0 : null,
          itemH: same ? pane.itemH ?? 1.0 : null,
        ),
      ),
    ),
    if (panes.every((pane) => pane.itemW != null)) ...[
      NumberStepper(
        label: 'Cells wide',
        value: shared(panes.map((pane) => pane.itemW!)),
        min: 1,
        max: panes.map((pane) => pane.columns).reduce((a, b) => a < b ? a : b),
        onChanged: (w) => onChanged((pane) => pane.copyWith(itemW: w * 1.0)),
      ),
      NumberStepper(
        label: 'Cells tall',
        value: shared(panes.map((pane) => pane.itemH ?? 1)),
        min: 1,
        max: Pane.maxRows,
        onChanged: (h) => onChanged((pane) => pane.copyWith(itemH: h * 1.0)),
      ),
    ],
  ]);

  /// Stands for "the pane does not decide" among the choices.
  static const _each = 'each';
}
