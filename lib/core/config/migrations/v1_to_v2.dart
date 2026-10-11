import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/legacy_sections.dart';
import 'package:openlauncher/core/layout/pane.dart';

/// The one wallpaper there could be is the first of the list there is now.
void wallpaperToWallpapers(Json save, Device device) {
  if (save['wallpapers'] is! List) {
    save['wallpapers'] = [if (save['wallpaper'] case final String path) path];
  }
  save.remove('wallpaper');
}

/// From before layouts there is only the order the cards were in: they go
/// in that order into the one pane a new home screen has. The order is
/// left where it was, for a layout that turns out not to be readable.
void orderToLayout(Json save, Device device) {
  if (save['layout'] is Map) return;
  save['layout'] = Layout.initial([...stringsIn(save['order'])]).toJson();
}

/// A panel's stack of sections becomes the one pane that fills it, each
/// section a pane inside that where it was and as big as it was.
void sectionsToPanes(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final panel in panelsOf(layout)) {
    final id = panel['id'];
    if (panel['pane'] == null && panel['sections'] != null && id is String) {
      panel['pane'] = paneFromSections(
        id,
        jsonList(panel, 'sections', Pane.fromJson),
      ).toJson();
    }
    panel.remove('sections');
  }
}

/// A sidebar was always a list of small rows, a picture with its name
/// beside it; now it looks however its pane says. The ones there were are
/// set up to look as they did.
void sidebarsAsRows(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final panel in panelsOf(layout)) {
    if (!const {'left', 'right', 'top', 'bottom'}.contains(panel['id'])) {
      continue;
    }
    if (panel['pane'] case final Json pane) {
      pane.addAll({'rowHeight': 36, 'itemLook': 'row', 'itemW': 1, 'itemH': 1});
    }
  }
}

/// Hidden cards were placed but not shown. They are taken off wherever
/// they are and listed as removed, which keeps them off.
void hiddenToRemoved(Json save, Device device) {
  final hidden = stringsIn(save.remove('hidden')).toSet();
  final layout = layoutOf(save);
  if (hidden.isEmpty || layout == null) return;
  for (final pane in panesOf(layout)) {
    if (pane['items'] case final List<Object?> items) {
      items.removeWhere(
        (item) =>
            item is Json &&
            (item['kind'] ?? 'card') == 'card' &&
            hidden.contains(item['ref']),
      );
    }
  }
  layout['removed'] = [
    ...{...stringsIn(layout['removed']), ...hidden},
  ];
}
