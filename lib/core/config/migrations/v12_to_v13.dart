import 'package:openlauncher/core/config/migrations/save_json.dart';

/// What the launcher draws of itself (a text, a picture, a button) is a
/// component, and an item that is one says so; it said `widget`.
void widgetsAsComponents(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      if (item['kind'] == 'widget') item['kind'] = 'component';
    }
  }
}
