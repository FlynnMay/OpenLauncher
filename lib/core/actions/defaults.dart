import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_registry.dart';
import 'package:openlauncher/core/actions/action_runner.dart';
import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// Default reveal/hide chains: a sidebar or folder moves to a new layer when
/// shown and the layer closes when hidden.
Triggers usualPanelTriggers(Panel panel) => switch (panel.kind) {
  PanelKind.sidebar => const {
    Trigger.reveal: [Act('newLayer'), Act('toLayer')],
    Trigger.hide: [Act('closeLayer')],
  },
  // A hovering folder dims what is below and takes the focus. An in-place one
  // needs no layer.
  PanelKind.popup when panel.rule('position') != 'inline' => const {
    Trigger.reveal: [
      Act('newLayer', {'dim': 0.54, 'modal': true}),
      Act('toLayer'),
    ],
    Trigger.hide: [Act('closeLayer')],
  },
  _ => const {},
};

/// The pane's own chains over the defaults.
Triggers panelTriggersOf(Panel panel) => {
  ...usualPanelTriggers(panel),
  ...panel.root.on,
};

/// A button that runs [kind], optionally on [entity].
Component actionButton(
  String id,
  ActionRegistry kind, {
  String? entity,
  Map<String, Object?> args = const {},
}) => Component(
  id: id,
  kind: ComponentRegistry.button.name,
  options: {'label': kind.label, 'icon': kind.icon},
  on: {
    Trigger.press: [
      Act(kind.name, {entityArg: ?entity, ...args}),
    ],
  },
);

/// The default quick actions, in order.
const usualMenu = ['open', 'info', 'forceStop', 'uninstall', 'remove'];

/// The default quick-actions popup.
Panel usualMenuPanel() => Panel(
  id: Layout.menuId,
  rules: const {'size': 'small'},
  root: Component.pane(
    id: Panel.rootId(Layout.menuId),
    columns: 1,
    rules: const {'rowHeight': 40, 'spacing': 4},
    // Set to the entity the menu was opened for.
    vars: const {Component.sourceVar: Variable(null, type: VarType.entity)},
    children: [
      for (final name in usualMenu)
        if (actionRegistry(name) case final kind?)
          actionButton(
            '${Layout.menuId}-${kind.name.toLowerCase()}',
            kind,
            args: {if (name == 'remove') 'what': '{{source.id}}'},
          ),
    ],
  ),
);
