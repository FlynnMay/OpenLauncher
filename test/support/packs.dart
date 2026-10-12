import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';
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
  iconSets: ['material'],
);

/// The Material pack installed, without touching the disk or the engine.
final List<Override> packOverrides = [
  packsProvider.overrideWith((ref) async => const [materialPack]),
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
