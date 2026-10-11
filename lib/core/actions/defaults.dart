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
    Trigger.reveal: [Act('newLayer', _layers), Act('toLayer', _layers)],
    Trigger.hide: [Act('closeLayer', _layers)],
  },
  // A hovering folder dims what is below and takes the focus. An in-place one
  // needs no layer.
  PanelKind.popup when panel.rule('position') != 'inline' => const {
    Trigger.reveal: [
      Act('newLayer', {..._layers, 'dim': 0.54, 'modal': true}),
      Act('toLayer', _layers),
    ],
    Trigger.hide: [Act('closeLayer', _layers)],
  },
  _ => const {},
};

const _layers = {entityArg: 'layers'};

/// The pane's own chains over the defaults.
Triggers panelTriggersOf(Panel panel) => {
  ...usualPanelTriggers(panel),
  ...panel.root.on,
};

/// A button that has [entity] do [action].
Component actionButton(
  String id,
  ActionRegistry action, {
  required String entity,
  Map<String, Object?> args = const {},
}) => Component(
  id: id,
  kind: ComponentRegistry.button.name,
  options: {'label': action.label, 'icon': action.icon},
  on: {
    Trigger.press: [
      Act(action.name, {entityArg: entity, ...args}),
    ],
  },
);

/// The default quick actions in order, each with the entity that does it.
const usualMenu = {
  'open': sourceEntity,
  'info': sourceEntity,
  'forceStop': sourceEntity,
  'uninstall': sourceEntity,
  'remove': 'layout',
};

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
      for (final MapEntry(key: name, value: entity) in usualMenu.entries)
        if (actionRegistry(name) case final action?)
          actionButton(
            '${Layout.menuId}-${name.toLowerCase()}',
            action,
            entity: entity,
            args: {if (name == 'remove') 'what': sourceEntity},
          ),
    ],
  ),
);
