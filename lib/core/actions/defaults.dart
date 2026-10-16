import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/layout.dart';

// What a new sidebar or folder is made with. All of it is
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
