import 'dart:math';

import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';

// Pane and panel settings described as data; editor forms are generated from
// these.

/// The transform fields for components whose parents are [parents]; only what
/// applies in all of them.
List<ComponentOption> transformOptions(Iterable<Component> parents) {
  // Rows and columns have flex and aspect, not cells.
  if (parents.every((pane) => pane.mode.inLine)) {
    return const [
      ComponentOption(
        'flex',
        'Share of the room',
        OptionKind.number,
        max: 12,
        unset: 'What it needs',
      ),
      ComponentOption(
        'aspect',
        'Shape (width for a height of 1)',
        OptionKind.number,
        max: 10,
        unset: 'Any',
      ),
    ];
  }
  final columns = parents.map((pane) => pane.columns).reduce(min);
  return [
    ComponentOption('w', 'Cells wide', OptionKind.number, min: 1, max: columns),
    const ComponentOption(
      'h',
      'Cells tall',
      OptionKind.number,
      min: 1,
      max: Component.maxRows,
    ),
    if (parents.every((pane) => pane.mode != PaneMode.flow)) ...[
      ComponentOption(
        'x',
        'Column',
        OptionKind.number,
        max: columns - 1,
        unset: 'Where it fits',
      ),
      const ComponentOption(
        'y',
        'Row',
        OptionKind.number,
        max: 999,
        unset: 'Where it fits',
      ),
    ],
  ];
}

/// Settings of every pane.
final List<ComponentOption> paneRules = [
  const ComponentOption('title', 'Title', OptionKind.text),
  const ComponentOption(
    'mode',
    'Placement',
    OptionKind.choice,
    usual: 'flow',
    choices: {
      'flow': 'In order',
      'grid': 'On cells',
      'free': 'Anywhere',
      'row': 'In a row',
      'column': 'In a column',
    },
  ),
  const ComponentOption(
    'columns',
    'Columns',
    OptionKind.number,
    usual: Component.defaultColumns,
    min: 1,
    max: Component.maxColumns,
    when: _onCells,
  ),
  ComponentOption(
    'rowHeight',
    'Row height',
    OptionKind.number,
    min: Component.minRowHeight.round(),
    max: Component.maxRowHeight.round(),
    step: 4,
    unset: 'By shape',
    when: _onCells,
  ),
  ComponentOption(
    'spacing',
    'Spacing',
    OptionKind.number,
    max: Component.maxSpacing.round(),
    step: 2,
    unset: 'Usual',
    when: _onCells,
  ),
  // Row and column panes only.
  const ComponentOption(
    'gap',
    'Gap',
    OptionKind.number,
    max: 80,
    step: 2,
    usual: 0,
    when: _inLine,
  ),
  const ComponentOption(
    'fit',
    'Made to fill its box',
    OptionKind.toggle,
    when: _inLine,
  ),
  const ComponentOption(
    'align',
    'Across',
    OptionKind.choice,
    unset: 'Usual',
    choices: {
      'start': 'At the start',
      'center': 'In the middle',
      'end': 'At the end',
      'stretch': 'Filling it',
    },
    when: _inLine,
  ),
];

bool _inLine(Map<String, Object?> options) =>
    options['mode'] == 'row' || options['mode'] == 'column';
bool _onCells(Map<String, Object?> options) => !_inLine(options);

/// Settings of a sidebar or a folder.
List<ComponentOption> panelRules(PanelKind kind) => switch (kind) {
  PanelKind.sidebar => const [
    // 0 hides it until the focus reaches its edge.
    ComponentOption(
      'closed',
      'Closed',
      OptionKind.number,
      max: 400,
      step: 8,
      unset: 'Usual',
    ),
    ComponentOption(
      'opening',
      'Opens by',
      OptionKind.choice,
      usual: 'expand',
      choices: {
        'expand': 'Growing from its edge',
        'slide': 'Sliding in',
        'fade': 'Fading in',
        'instant': 'At once',
      },
    ),
    ComponentOption(
      'reveal',
      'What is in it',
      OptionKind.choice,
      usual: 'always',
      choices: {
        'always': 'Always there',
        'fade': 'Fade in',
        'late': 'Fade in once it is open',
        'slide': 'Slide in',
      },
    ),
  ],
  PanelKind.popup => const [
    ComponentOption(
      'position',
      'Opens',
      OptionKind.choice,
      usual: 'center',
      choices: {
        'center': 'Centre',
        'bottom': 'Bottom',
        'left': 'Left',
        'right': 'Right',
        'inline': 'In place',
      },
    ),
    ComponentOption(
      'size',
      'Size',
      OptionKind.choice,
      usual: 'medium',
      choices: {'small': 'Small', 'medium': 'Medium', 'large': 'Large'},
    ),
  ],
  PanelKind.home => const [],
};
