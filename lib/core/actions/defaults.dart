import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/entities/entity_generators.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variable.dart';

// What a new sidebar, folder or quick-actions menu is made with. All of it is
// ordinary data on the pane; nothing here is implied for a pane without it.

const _layers = {entityArg: 'layers'};

Act _open(bool open) =>
    Act('set', {entityArg: 'variables', 'var': 'open', 'value': open});

/// A sidebar's chains: open while it has the focus, on a layer of its own.
Triggers barTriggers() => {
  Trigger.focus: [_open(true)],
  Trigger.blur: [_open(false)],
  Trigger.reveal: const [Act('newLayer', _layers), Act('toLayer', _layers)],
  Trigger.hide: const [Act('closeLayer', _layers)],
};

/// A hovering folder's chains: a layer that dims what is below and takes the
/// focus. One opened in place needs no layer.
Triggers folderTriggers({bool inPlace = false}) => inPlace
    ? const {}
    : const {
        Trigger.reveal: [
          Act('newLayer', {..._layers, 'dim': 0.54, 'modal': true}),
          Act('toLayer', _layers),
        ],
        Trigger.hide: [Act('closeLayer', _layers)],
      };

/// The look of a new folder.
const folderStyle = {'background': '#1a1c23fa', 'radius': 18, 'padding': 28};

/// [pane] docked to [edge] as a sidebar: on a side it closes to a strip, on
/// top or bottom it hides; it opens while it has the focus.
Component asSidebar(Component pane, String edge) => pane
    .withOption('dock', edge)
    .withOption('closed', edge == 'top' || edge == 'bottom' ? 0 : 96)
    .copyWith(on: {...barTriggers(), ...pane.on});

/// A new sidebar on [edge]: one column of rows on a side, one row on top or
/// bottom.
Component sidebarPane(String id, String edge) => asSidebar(
  edge == 'top' || edge == 'bottom'
      ? Component.pane(id: id, columns: 8)
      : Component.pane(id: id, columns: 1).asBar(),
  edge,
);

/// A new folder, hovering in the middle.
Component folderPane(String id, {String title = ''}) => Component.pane(
  id: id,
  title: title,
  columns: 4,
  rules: const {'dock': 'center', 'opening': 'instant'},
  style: folderStyle,
  on: folderTriggers(),
);

/// A button that has [entity] do its action called [name], labelled as
/// [action] is.
Component actionButton(
  String id,
  String name,
  EntityAction action, {
  required String entity,
  Map<String, Object?> args = const {},
}) => Component(
  id: id,
  kind: ComponentRegistry.button.name,
  options: {
    'label': action.label.isEmpty ? name : action.label,
    'icon': action.icon,
  },
  on: {
    Trigger.press: [
      Act(name, {entityArg: entity, ...args}),
    ],
  },
);

/// The default quick actions in order, each with the entity that does it.
const usualMenu = {
  'open': sourceEntity,
  'info': sourceEntity,
  'forceStop': sourceEntity,
  'uninstall': sourceEntity,
  'remove': Layout.homeId,
};

/// The default quick-actions pane: a small folder titled after what it was
/// opened for.
Component usualMenuPane() {
  // Labelled as an app and the home layout have them.
  final known = {...appActions, ...layoutEntity(Layout.homeId).actions};
  return Component.pane(
    id: Layout.menuId,
    title: '{{source.label}}',
    columns: 1,
    rules: const {
      'dock': 'center',
      'width': 432,
      'opening': 'instant',
      'rowHeight': 40,
      'spacing': 4,
    },
    style: folderStyle,
    on: folderTriggers(),
    // Set to the entity the menu was opened for.
    vars: const {Component.sourceVar: Variable(null, type: VarType.entity)},
    children: [
      for (final MapEntry(key: name, value: entity) in usualMenu.entries)
        if (known[name] case final action?)
          actionButton(
            '${Layout.menuId}-${name.toLowerCase()}',
            name,
            action,
            entity: entity,
            args: {if (name == 'remove') 'what': sourceEntity},
          ),
    ],
  );
}
