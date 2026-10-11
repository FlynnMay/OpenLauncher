import 'package:openlauncher/core/config/migrations/save_json.dart';

/// What opens a folder is no longer a kind of item of its own: it is an
/// instance of a prefab, `folder-card` unless it named another among its
/// options, drawn from the folder, which is its variable `source`.
void foldersAsInstances(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      if (item['kind'] != 'panel') continue;
      var prefab = 'folder-card';
      if (item['options'] case final Json options) {
        if (options.remove('prefab') case final String named) prefab = named;
        if (options.isEmpty) item.remove('options');
      }
      item['kind'] = 'prefab';
      item['vars'] = <String, Object?>{
        if (item['vars'] case final Map<Object?, Object?> there)
          ...there.cast(),
        'source': item['ref'],
      };
      item['ref'] = prefab;
    }
  }
}
