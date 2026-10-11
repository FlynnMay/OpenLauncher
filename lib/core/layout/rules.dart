import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';

// The rules of a pane, and of the panes that are shown and hidden: each
// one setting, described once, under the name it is saved by. The editor
// draws its forms from these and changes the thing by that name; a new
// rule is a line here and its use where the pane is drawn.

/// What every pane says of how it arranges what is in it.
final List<ComponentOption> paneRules = [
  const ComponentOption('title', 'Title', OptionKind.text),
  const ComponentOption(
    'mode',
    'Placement',
    OptionKind.choice,
    usual: 'flow',
    choices: {'flow': 'In order', 'grid': 'On cells', 'free': 'Anywhere'},
  ),
  const ComponentOption(
    'columns',
    'Columns',
    OptionKind.number,
    usual: Pane.defaultColumns,
    min: 1,
    max: Pane.maxColumns,
  ),
  ComponentOption(
    'rowHeight',
    'Row height',
    OptionKind.number,
    min: Pane.minRowHeight.round(),
    max: Pane.maxRowHeight.round(),
    step: 4,
    unset: 'By shape',
  ),
  ComponentOption(
    'spacing',
    'Spacing',
    OptionKind.number,
    max: Pane.maxSpacing.round(),
    step: 2,
    unset: 'Usual',
  ),
];

/// What a pane that is shown and hidden says of how: a sidebar's rules,
/// and a folder's. They differ only in these.
List<ComponentOption> panelRules(Panel panel) => switch (panel.kind) {
  PanelKind.sidebar => const [
    // How much of it shows while the focus is elsewhere; 0 keeps it out
    // of sight until the focus goes to its edge.
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
