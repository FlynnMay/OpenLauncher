import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/templates.dart';
import 'package:openlauncher/features/components/pack_icon.dart';

/// The launcher's own Material set as `tool/material_pack.dart` wrote it,
/// with no font loaded.
final materialSet = IconSet.fromJson(
  'material',
  jsonDecode(File('packs/material/icons/material.json').readAsStringSync()),
)!;

const materialPack = Pack(
  id: 'material',
  name: 'Material Symbols',
  version: '1',
  author: 'Google',
  licence: 'Apache-2.0',
  builtIn: true,
  bytes: 2 << 20,
  files: ['fonts/material-symbols-outlined.ttf', 'icons/material.json'],
);

/// The launcher's own System pack as it is in `packs/system`.
final systemPack =
    Pack.fromJson(
      jsonDecode(File('packs/system/pack.json').readAsStringSync()),
    )!.copyWith(
      builtIn: true,
      files: [
        for (final file in Directory('packs/system').listSync(recursive: true))
          if (file is File && !file.path.endsWith('pack.json'))
            file.path.substring('packs/system/'.length),
      ]..sort(),
    );

/// The System pack's prefabs as the launcher reads them, by file name: the
/// app card first.
List<Prefab> get systemPrefabs => _systemContents.prefabs;

final _systemContents = PackContents.parse(systemPack, {
  for (final path in systemPack.files.where(PackContents.reads))
    path: File('packs/system/$path').readAsStringSync(),
});

/// The System pack's starting layout, with [order] placed in its inbox.
Layout homeLayout([List<String> order = const []]) {
  final home = _systemContents.layouts[_systemContents.start]!;
  return home.rebuild(
    (pane, items) => pane.id != home.inbox
        ? items
        : [
            ...items,
            for (final id in order) cardOf(id, id: Component.autoId(id)),
          ],
  );
}

// What the System pack names, as tests write it.
const cardPrefabId = 'system:app-card';
const folderPrefabId = 'system:folder-card';
const folderTemplateId = 'system:folder';
const sidebarTemplateId = 'system:sidebar';
const appCategory = 'app';
const inputCategory = 'input';
const launcherCategory = 'launcher';
const sourceEntity = '{{source.id}}';
String appId(String package) => 'system:app/$package';
String inputId(String input) => 'system:input/$input';

/// The System pack's prefab [id].
Prefab systemPrefab(String id) =>
    systemPrefabs.firstWhere((prefab) => prefab.id == id);

/// The System pack's prefabs by id.
Map<String, Prefab> get systemPrefabMap => {
  for (final prefab in systemPrefabs) prefab.id: prefab,
};

/// An instance of [prefab], the app card unless said, handed [entityId] in
/// its `source` variable, as the System pack's cards take it.
Component cardOf(
  String entityId, {
  required String id,
  String prefab = cardPrefabId,
  double w = 1,
  double h = 1,
  double? x,
  double? y,
  String? variant,
  Overrides overrides = const {},
  Style style = const {},
  Triggers on = const {},
}) => Component.of(
  entityId,
  id: id,
  prefab: prefab,
  variable: 'source',
  w: w,
  h: h,
  x: x,
  y: y,
  variant: variant,
  overrides: overrides,
  style: style,
  on: on,
);

/// [cardOf] as `withEntities` places an entity.
Component? placedCard(String entityId, String id) => cardOf(entityId, id: id);

/// A new folder, as the editor makes it from the System pack's template.
Component folderPane(String id, {String title = ''}) =>
    folderFrom(systemPrefab(folderTemplateId), id, title: title);

/// A new sidebar on [edge], as the editor makes it from the System pack's
/// template.
Component sidebarPane(String id, String edge) =>
    sidebarFrom(systemPrefab(sidebarTemplateId), id, edge);

/// The chains of a sidebar made from the System pack's template.
Triggers barTriggers() => systemPrefab(sidebarTemplateId).root.on;

/// The chains of a folder made from the System pack's template.
Triggers folderTriggers() => systemPrefab(folderTemplateId).root.on;

/// A new config, as the store gives it: the starting layout, not the user's.
LauncherConfig get startingConfig =>
    LauncherConfig(layout: homeLayout(), ownLayout: false);

/// What the System pack holds, for the editor's tests, whose packs come
/// from a stand-in TV.
final systemContents = packContentsProvider.overrideWith(
  (ref) async => [_systemContents],
);

/// The packs in `packs/` installed, read from there rather than through the
/// pack store, and no font loaded.
final List<Override> packOverrides = [
  packsProvider.overrideWith((ref) async => [materialPack, systemPack]),
  // Read at once: real file reads never finish under a widget test's clock.
  packReaderProvider.overrideWithValue((pack, path) async {
    final file = File('packs/${pack.id}/$path');
    return file.existsSync() ? file.readAsBytesSync() : null;
  }),
  packPictureProvider.overrideWithValue((picture) async {
    final file = File(picture.replaceFirst('pack:', 'packs/'));
    return file.existsSync() ? file.absolute.path : null;
  }),
  iconSetProvider.overrideWith(
    (ref, id) async => id == 'material' ? materialSet : null,
  ),
];

/// The drawn icon saved as [name].
Finder packIcon(String name) => find.byWidgetPredicate(
  (widget) => widget is PackIcon && widget.name == name,
);

/// Enough of a font for the store, which only looks at how it starts.
final fontBytes = Uint8List.fromList([0, 1, 0, 0, 0, 0, 0, 0]);

/// A zip of [files], by path; a string is written as text.
Uint8List zipOf(Map<String, Object> files) {
  final archive = Archive();
  for (final MapEntry(key: path, value: content) in files.entries) {
    archive.add(
      ArchiveFile.bytes(
        path,
        content is String ? utf8.encode(content) : content as List<int>,
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A pack's zip: [id] with one icon set of the same name holding [icons].
Uint8List packZip(
  String id, {
  String version = '1',
  Map<String, int> icons = const {'lamp': 0xe001},
}) => zipOf({
  'pack.json': jsonEncode({'id': id, 'name': 'Pack $id', 'version': version}),
  'fonts/$id.ttf': fontBytes,
  'icons/$id.json': jsonEncode({
    'name': 'Icons $id',
    'font': '$id.ttf',
    'categories': ['Things'],
    'icons': {
      for (final MapEntry(key: name, value: code) in icons.entries)
        name: [code, 0, 'light bulb'],
    },
  }),
});

/// A zip of the pack in `packs/<id>`, as `tool/build_packs.dart` makes it.
Uint8List folderZip(String id) => zipOf({
  for (final file in Directory('packs/$id').listSync(recursive: true))
    if (file is File)
      file.path.substring('packs/$id/'.length): file.readAsBytesSync(),
});

/// Lets [container]'s pack store finish unpacking into its folder, which a
/// test is about to delete, then disposes it.
Future<void> closePacks(ProviderContainer container) async {
  try {
    await container.read(packStoreProvider).list();
  } on Object {
    // Nothing is being written.
  }
  container.dispose();
}

/// The app's assets holding [zips] as built-in packs, by id.
class BundledPacks extends CachingAssetBundle {
  BundledPacks([this.zips = const {}]);

  final Map<String, Uint8List> zips;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/packs/index.json') {
      return ByteData.sublistView(
        utf8.encode(
          jsonEncode({
            for (final MapEntry(key: id, value: zip) in zips.entries)
              id: '${getCrc32(zip)}',
          }),
        ),
      );
    }
    final id = key.split('/').last.replaceAll('.zip', '');
    if (zips[id] case final zip?) return ByteData.sublistView(zip);
    throw FlutterError('No asset $key');
  }
}
