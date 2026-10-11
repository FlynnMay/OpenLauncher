import 'package:openlauncher/core/config/migrations/save_json.dart';

void _opens(Object? on) {
  if (on is! Json) return;
  for (final acts in on.values) {
    if (acts is! List<Object?>) continue;
    for (final act in acts) {
      if (act is Json && act['do'] == 'panel') {
        act['do'] = 'set';
        act['var'] = 'open';
        act['value'] = true;
        act['of'] = act.remove('panel');
      }
    }
  }
}

/// A folder is opened by setting its `open` variable, not by an action of
/// its own: what was told to open a folder is told to set that.
void foldersOpenByVariable(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout != null) {
    for (final pane in panesOf(layout)) {
      for (final item in itemsOf(pane)) {
        _opens(item['on']);
      }
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    _opens(prefab['on']);
  }
}
