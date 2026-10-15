import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variable.dart';

// What a new sidebar, folder or quick-actions menu is made with. All of it is
// ordinary data on the pane; nothing here is implied for a pane without it.

const _new = 'launcher://layers/new',
    _raise = Act('launcher://layers/raise'),
    _close = Act('launcher://layers/close');

Act _open(bool open) =>
    Act('launcher://variables/set', {'var': 'open', 'value': open});

/// A sidebar's chains: open while it has the focus, on a layer of its own.
Triggers barTriggers() => {
  Trigger.focus: [_open(true)],
  Trigger.blur: [_open(false)],
  Trigger.reveal: const [Act(_new), _raise],
  Trigger.hide: const [_close],
};

/// A hovering folder's chains: a layer that dims what is below and takes the
/// focus. One opened in place needs no layer.
Triggers folderTriggers({bool inPlace = false}) => inPlace
    ? const {}
    : const {
        Trigger.reveal: [
          Act(_new, {'dim': 0.54, 'modal': true}),
          _raise,
        ],
        Trigger.hide: [_close],
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

/// A button that does [act].
Component _actionButton(
  String id,
  Act act, {
  required String label,
  required String icon,
}) => Component(
  id: id,
  kind: ComponentRegistry.button.name,
  options: {'label': label, 'icon': icon},
  on: {
    Trigger.press: [act],
  },
);

/// The default quick actions in order: what each does, and its button.
const defaultMenu = {
  'open': (
    act: Act('open', {entityArg: sourceEntity}),
    label: 'Open',
    icon: 'material:play_arrow',
  ),
  'info': (
    act: Act('info', {entityArg: sourceEntity}),
    label: 'App info',
    icon: 'material:info',
  ),
  'uninstall': (
    act: Act('uninstall', {entityArg: sourceEntity}),
    label: 'Uninstall',
    icon: 'material:delete',
  ),
  'remove': (
    act: Act('launcher://layout/remove', {
      'layer': Layout.homeId,
      'what': sourceEntity,
    }),
    label: 'Remove',
    icon: 'material:do_not_disturb_on',
  ),
};

/// The default quick-actions pane: a small folder titled after what it was
/// opened for.
Component defaultMenuPane() => Component.pane(
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
    for (final MapEntry(key: name, value: (:act, :label, :icon))
        in defaultMenu.entries)
      _actionButton('${Layout.menuId}-$name', act, label: label, icon: icon),
  ],
);
