import 'package:openlauncher/core/config/migrations/save_json.dart';

/// What an instance is drawn from was a thing of its own, `source`; it is
/// one of its variables now, the one its prefab reads by that name.
void sourceAsVariable(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      if (item.remove('source') case final String source) {
        item['vars'] = <String, Object?>{
          if (item['vars'] case final Map<Object?, Object?> there)
            ...there.cast(),
          'source': source,
        };
      }
    }
  }
}
