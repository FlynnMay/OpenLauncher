import 'dart:math';

import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';

// Pane settings described as data; editor forms are generated from these.

/// The transform fields for components whose parents are [parents]; only what
/// applies in all of them.
List<ComponentOption> transformOptions(Iterable<Component> parents) {
  // Rows and columns have flex and aspect, not cells.
  if (parents.every((pane) => pane.mode.inLine)) {
    return const [
      ComponentOption(
        'flex',
        'Flex',
        OptionKind.number,
        max: 12,
        unset: 'Auto',
      ),
      ComponentOption(
        'aspect',
        'Aspect ratio',
        OptionKind.number,
        max: 10,
        unset: 'Auto',
      ),
    ];
  }
  final columns = parents.map((pane) => pane.reach).reduce(min);
  return [
    ComponentOption(
      'w',
      'Width (cells)',
      OptionKind.number,
      min: 1,
      max: columns,
    ),
    const ComponentOption(
      'h',
      'Height (cells)',
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
        unset: 'Auto',
      ),
      const ComponentOption(
        'y',
        'Row',
        OptionKind.number,
        max: 999,
        unset: 'Auto',
      ),
    ],
  ];
}

/// Settings of every pane.
final List<ComponentOption> paneRules = [
  const ComponentOption('title', 'Title', OptionKind.text),
  const ComponentOption(
    'mode',
    'Layout',
    OptionKind.choice,
    defaultValue: 'flow',
    choices: {
      'flow': 'Flow',
      'grid': 'Grid',
      'free': 'Free',
      'row': 'Row',
      'column': 'Column',
    },
  ),
  const ComponentOption(
    'columns',
    'Columns',
    OptionKind.number,
    defaultValue: Component.defaultColumns,
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
    unset: 'Auto',
    when: _onCells,
  ),
  ComponentOption(
    'spacing',
    'Spacing',
    OptionKind.number,
    max: Component.maxSpacing.round(),
    step: 2,
    unset: 'Default',
    when: _onCells,
  ),
  // Row and column panes only.
  const ComponentOption(
    'gap',
    'Gap',
    OptionKind.number,
    max: 80,
    step: 2,
    defaultValue: 0,
    when: _inLine,
  ),
  const ComponentOption(
    'fit',
    'Stretch to fit',
    OptionKind.toggle,
    when: _inLine,
  ),
  const ComponentOption(
    'align',
    'Align',
    OptionKind.choice,
    unset: 'Default',
    choices: {
      'start': 'Start',
      'center': 'Centre',
      'end': 'End',
      'stretch': 'Stretch',
    },
    when: _inLine,
  ),
  const ComponentOption(
    'scrollX',
    'Horizontal scroll',
    OptionKind.toggle,
    defaultValue: false,
    when: _canScrollAcross,
  ),
  // Cells scroll down unless told not to.
  const ComponentOption(
    'scrollY',
    'Vertical scroll',
    OptionKind.toggle,
    defaultValue: true,
    when: _onCells,
  ),
  const ComponentOption(
    'scrollY',
    'Vertical scroll',
    OptionKind.toggle,
    defaultValue: false,
    when: _canScrollDown,
  ),
  const ComponentOption(
    'scrollbar',
    'Scroll bar',
    OptionKind.choice,
    unset: 'None',
    choices: {'thumb': 'Thumb', 'progress': 'Progress'},
    when: _scrolls,
  ),
  const ComponentOption(
    'scrollbarShow',
    'Show scroll bar',
    OptionKind.choice,
    defaultValue: 'always',
    choices: {'always': 'Always', 'auto': 'While scrolling'},
    when: _hasScrollbar,
  ),
];

bool _scrolls(Map<String, Object?> options) => _onCells(options)
    ? options['scrollY'] != false || options['scrollX'] == true
    : _canScrollAcross(options) && options['scrollX'] == true ||
          _canScrollDown(options) && options['scrollY'] == true;
bool _hasScrollbar(Map<String, Object?> options) =>
    _scrolls(options) && Component.scrollbars.contains(options['scrollbar']);

// A fitted row or column is scaled to its box, so has nothing to scroll.
bool _canScrollAcross(Map<String, Object?> options) =>
    _onCells(options) || options['mode'] == 'row' && options['fit'] != true;
bool _canScrollDown(Map<String, Object?> options) =>
    options['mode'] == 'column' && options['fit'] != true;

bool _inLine(Map<String, Object?> options) =>
    options['mode'] == 'row' || options['mode'] == 'column';
bool _onCells(Map<String, Object?> options) => !_inLine(options);

const _edges = {
  'left': 'Left edge',
  'right': 'Right edge',
  'top': 'Top edge',
  'bottom': 'Bottom edge',
};

/// Where a pane is docked and, once it is, how it opens. Any pane can be
/// docked to an edge; one hidden while closed (a folder) can also sit in the
/// middle or in what opens it, and cannot be undocked, since its cards name
/// it.
List<ComponentOption> dockRules(Component pane) => [
  ComponentOption(
    'dock',
    'Position',
    OptionKind.choice,
    unset: pane.hovers ? null : 'None',
    choices: {
      ..._edges,
      if (pane.hovers) ...const {
        'center': 'Centre',
        Component.inline: 'Inline',
      },
    },
  ),
  // 0 leaves it at its edge with nothing showing.
  if (pane.isDocked && !pane.hovers)
    const ComponentOption(
      'closed',
      'Collapsed size',
      OptionKind.number,
      max: 400,
      step: 8,
      defaultValue: 0,
    ),
  if (pane.isDocked && pane.dock != Component.inline) ...const [
    ComponentOption(
      'opening',
      'Animation',
      OptionKind.choice,
      defaultValue: 'expand',
      choices: {
        'expand': 'Expand',
        'slide': 'Slide',
        'fade': 'Fade',
        'instant': 'None',
      },
    ),
    ComponentOption(
      'reveal',
      'Content animation',
      OptionKind.choice,
      defaultValue: 'always',
      choices: {
        'always': 'None',
        'fade': 'Fade',
        'late': 'Fade after opening',
        'slide': 'Slide',
      },
    ),
  ],
];

/// The options only a docked pane has.
const dockKeys = ['dock', 'closed', 'width', 'height', 'opening', 'reveal'];

/// A docked pane's rule, or its default.
Object? dockRule(Component pane, String key) =>
    pane.options[key] ??
    dockRules(pane).where((rule) => rule.key == key).firstOrNull?.defaultValue;
