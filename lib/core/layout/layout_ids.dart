import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/pane.dart';

/// [name] as an id that can be read: in small letters, its words joined by
/// dashes. [fallback] when nothing of it is left, as with a name in another
/// script.
String slugOf(String name, [String fallback = 'item']) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// The parts a package name starts with that say where its maker is found
/// and not what the app is.
const _registries = {
  'com', 'org', 'net', 'io', 'co', 'app', 'dev', 'me', 'tv', 'edu', 'gov', //
  'info', 'xyz',
};

/// The sites that give everyone a package name, the next part of which is
/// only who.
const _hosts = {'gh', 'github', 'gitlab', 'codeberg'};

/// An app's [package] name as an id that can be read: without the parts
/// that only say where its maker is found, so `au.com.tenplay` is
/// `tenplay` and `io.github.someone.player.tv` is `player-tv`.
String packageSlug(String package) {
  var parts = package.split('.').where((part) => part.isNotEmpty).toList();
  bool registry(String part) =>
      !_hosts.contains(part) &&
      (_registries.contains(part) || part.length == 2);
  while (parts.length > 1 && registry(parts.first.toLowerCase())) {
    parts = parts.sublist(1);
  }
  if (parts.length > 2 && _hosts.contains(parts.first.toLowerCase())) {
    parts = parts.sublist(2);
  }
  return slugOf(parts.join('-'), 'app');
}

/// [wanted], or [wanted] with the first number after it that makes an id
/// not among those [used].
String freeId(String wanted, Set<String> used) {
  var id = wanted;
  for (var n = 2; used.contains(id); n++) {
    id = '$wanted-$n';
  }
  return id;
}

/// The ids a layout's things go by, made to say what each thing is.
extension LayoutIds on Layout {
  Iterable<Pane> get _panes => panels.expand((panel) => panel.root.panes);

  /// The ids taken by items, by panes and by panels; the sidebars' and the
  /// home screen's count as taken whether or not they are there.
  Set<String> get itemIds => {
    for (final pane in _panes)
      for (final item in pane.items) item.id,
  };
  Set<String> get paneIds => {for (final pane in _panes) pane.id};
  Set<String> get panelIds => {
    Layout.homeId,
    ...Layout.barIds,
    for (final panel in panels) panel.id,
  };

  /// An id for a new item called [name]: a folder's name, the kind of
  /// widget, or for a card what [LayoutItem.autoId] makes of it.
  String itemIdFor(String name) => freeId(slugOf(name), itemIds);

  /// An id for a new pane.
  String paneIdFor([String title = '']) =>
      freeId(slugOf(title, 'pane'), paneIds);

  /// An id for a new popup called [title].
  String panelIdFor(String title) => freeId(slugOf(title, 'folder'), panelIds);
}
