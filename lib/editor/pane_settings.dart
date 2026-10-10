import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls.dart';
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
    this.children = const [],
  });

  /// The heading the settings go under.
  final String title;
  final List<Pane> panes;

  /// Called with how each of the panes is to change.
  final void Function(Pane Function(Pane pane) change) onChanged;

  /// Whether a pane's own title is among its settings.
  final bool named;

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
    ...children,
  ]);
}
