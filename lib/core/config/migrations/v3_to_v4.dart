import 'package:openlauncher/core/config/migrations/save_json.dart';

/// What each quick action was called and drawn with when this step was
/// written; `hide` is what `remove` was called before that.
const _buttons = {
  'open': ('Open', 'play'),
  'info': ('App info', 'info'),
  'forceStop': ('Force stop', 'stop'),
  'uninstall': ('Uninstall', 'delete'),
  'remove': ('Remove', 'remove'),
  'hide': ('Remove', 'remove'),
};

const _menu = 'quick-actions';

/// The list of quick actions a held card offers becomes a popup in the
/// layout, with a button for each in the same order: the menu is a folder
/// like any other, and what its buttons do is theirs to say. A save with
/// no list of its own is given the usual ones when it is read.
void menuAsPanel(Json save, Device device) {
  final chosen = save.remove('contextMenu');
  final layout = layoutOf(save);
  if (layout == null || chosen is! List<Object?>) return;
  if (panelsOf(layout).any((panel) => panel['id'] == _menu)) return;
  final names = <String>{
    for (final name in stringsIn(chosen))
      if (_buttons.containsKey(name)) name == 'hide' ? 'remove' : name,
  };
  (layout['panels'] as List<Object?>).add({
    'id': _menu,
    'title': '',
    'position': 'center',
    'size': 'small',
    'pane': {
      'id': '$_menu/root',
      'title': '',
      'mode': 'flow',
      'columns': 1,
      'rowHeight': 40,
      'spacing': 4,
      'items': [
        for (final name in names)
          {
            'id': '$_menu-${name.toLowerCase()}',
            'kind': 'widget',
            'ref': 'button',
            'w': 1,
            'h': 1,
            'options': {
              'label': _buttons[name]!.$1,
              'icon': _buttons[name]!.$2,
            },
            'on': {
              'press': [
                {'do': name},
              ],
            },
          },
      ],
    },
  });
}
