import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_item.dart';

/// The ids given before they were made to be read: random letters after an
/// `i`, `s` or `p`, a card's whole id, or a pane's after `pane:`.
final _unreadable = RegExp(r'^([isp][0-9a-z]{7}|auto:.*|pane:.*)$');

/// Every such id becomes one that says what the thing is: an app's after
/// its package, any other card's after what the device calls it, a
/// folder's and a pane's after its title, a widget's after its kind.
///
/// An app widget keeps its id, which is what the device knows it by. What
/// goes by an id follows it: the inbox, the items that open a folder or
/// hold a pane, and the pictures given to folders.
void readableIds(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  bool kept(String id) => !_unreadable.hasMatch(id);
  String text(Json json, String key) => switch (json[key]) {
    final String value => value,
    _ => '',
  };
  Set<String> keptIds(Iterable<Json> things) => {
    for (final thing in things)
      if (text(thing, 'id') case final id when kept(id)) id,
  };
  String take(Set<String> used, String wanted) {
    final id = freeId(wanted, used);
    used.add(id);
    return id;
  }

  final panels = panelsOf(layout);
  final panes = panesOf(layout).toList();
  final items = [for (final pane in panes) ...itemsOf(pane)];
  final panelIds = {
    'home',
    'left',
    'right',
    'top',
    'bottom',
    ...keptIds(panels),
  };
  final paneIds = keptIds(panes), itemIds = keptIds(items);

  final renamed = <String, String>{};
  for (final panel in panels) {
    final id = text(panel, 'id');
    if (kept(id)) continue;
    panel['id'] = renamed[id] = take(
      panelIds,
      slugOf(text(panel, 'title'), 'folder'),
    );
  }
  final titles = {
    for (final panel in panels) text(panel, 'id'): text(panel, 'title'),
  };

  // A popup's own pane is named after it, and goes on being.
  final moved = {
    for (final MapEntry(key: old, value: next) in renamed.entries)
      '$old/root': '$next/root',
  };
  for (final pane in panes) {
    final id = text(pane, 'id');
    if (pane['id'] is! String) continue;
    pane['id'] =
        moved[id] ??
        (kept(id)
            ? id
            : moved[id] = take(paneIds, slugOf(text(pane, 'title'), 'pane')));
  }

  for (final item in items) {
    final kind = switch (item['kind']) {
      final String kind => kind,
      _ => 'card',
    };
    final ref = switch (item) {
      {'pane': {'id': final String pane}} when kind == 'pane' => pane,
      _ when kind == 'panel' => renamed[item['ref']] ?? text(item, 'ref'),
      _ => text(item, 'ref'),
    };
    if (item['ref'] is String || kind == 'pane') item['ref'] = ref;
    final id = item['id'];
    if (id is! String || kept(id)) continue;
    if (kind == 'widget' && ref == 'android') continue;
    item['id'] = take(itemIds, switch (kind) {
      'panel' => slugOf(titles[ref] ?? '', 'folder'),
      'widget' => slugOf(ref, 'widget'),
      'pane' => LayoutItem.paneItemId(ref),
      _ => LayoutItem.autoId(ref, device.names[ref]),
    });
  }

  if (layout['inbox'] case final String inbox) {
    layout['inbox'] = moved[inbox] ?? inbox;
  }
  if (save['iconOverrides'] case final Json icons) {
    for (final MapEntry(key: old, value: next) in renamed.entries) {
      if (icons.remove('panel:$old') case final picture?) {
        icons['panel:$next'] = picture;
      }
    }
  }
}
