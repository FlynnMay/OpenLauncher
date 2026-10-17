import 'package:openlauncher/core/layout/layout_model.dart';

/// [name] as a lowercase dashed id; [fallback] if nothing is left.
String slugOf(String name, [String fallback = 'item']) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// Leading package-name parts that carry no meaning.
const _registries = {
  'com', 'org', 'net', 'io', 'co', 'app', 'dev', 'me', 'tv', 'edu', 'gov', //
  'info', 'xyz',
};

/// Code hosts whose next part is only a username.
const _hosts = {'gh', 'github', 'gitlab', 'codeberg'};

/// A readable id from a package name: `au.com.tenplay` -> `tenplay`,
/// `io.github.someone.player.tv` -> `player-tv`.
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

/// [wanted], suffixed with a number if it is in [used].
String freeId(String wanted, Set<String> used) {
  var id = wanted;
  for (var n = 2; used.contains(id); n++) {
    id = '$wanted-$n';
  }
  return id;
}

extension LayoutIds on Layout {
  /// Ids in use. Containers and other nodes share one id space.
  Set<String> get itemIds => {
    Layout.homeId,
    for (final component in all) component.id,
  };

  /// A new component id from [name].
  String itemIdFor(String name) => freeId(slugOf(name), itemIds);

  String containerIdFor([String title = '', String fallback = 'pane']) =>
      freeId(slugOf(title, fallback), itemIds);
}
