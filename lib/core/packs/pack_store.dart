import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/icon_set.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where installed packs are kept, a folder each.
final packsDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'packs'));
});

/// Holds the packs that ship with the launcher, as `tool/build_packs.dart`
/// lays them out. Overridden in tests.
final bundledPacksProvider = Provider<AssetBundle>((ref) => rootBundle);

final packStoreProvider = Provider<PackStore>((ref) {
  final store = PackStore(ref);
  ref.onDispose(store.dispose);
  return store;
});

const _picture = 'pack:';

/// Whether [value] names a pack's picture: `pack:<id>/images/<name>`.
bool isPackPicture(Object? value) =>
    value is String &&
    value.startsWith(_picture) &&
    value.contains('/images/', _picture.length);

/// The file a `pack:` picture is; null if none. Overridden in tests.
final packPictureProvider = Provider<Future<String?> Function(String picture)>(
  (ref) => ref.watch(packStoreProvider).pictureAt,
);

/// Why a pack was turned down, as an HTTP status.
class PackRefused implements Exception {
  const PackRefused(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// The installed packs, unpacked on disk. The built-in ones are unpacked
/// from the app's assets through the same door as an upload. Listeners are
/// told when a pack is installed or removed.
class PackStore with ChangeNotifier {
  PackStore(this._ref);

  static const maxZipBytes = 32 * 1024 * 1024;
  static const maxBytes = 64 * 1024 * 1024;

  static const _assets = 'assets/packs/';
  static const _manifest = 'pack.json';

  /// Holds the hash of the bundled zip a built-in pack was unpacked from.
  static const _stamp = '.bundled';

  /// The only files a pack is read for; anything else in a zip is left.
  static final _kept = RegExp(
    r'^(pack\.json|fonts/[A-Za-z0-9._-]+\.(ttf|otf)'
    r'|(icons|entities|sources|generators|prefabs)/[a-z0-9][a-z0-9_-]*\.json'
    r'|images/[a-z0-9][a-z0-9_-]*\.(svg|png|webp))$',
  );

  final Ref _ref;

  /// The built-in packs' ids, once they are unpacked.
  Future<Set<String>>? _builtIn;

  Future<Directory> _dir() => _ref.read(packsDirProvider.future);

  /// Unpacks every bundled pack that is new or has changed.
  Future<Set<String>> _unpackBundled() async {
    final bundle = _ref.read(bundledPacksProvider);
    final Map<Object?, Object?> index;
    try {
      index = jsonDecode(
        await bundle.loadString('${_assets}index.json', cache: false),
      ) as Map;
    } on FlutterError {
      return const {};
    }
    final dir = await _dir();
    final ids = <String>{};
    for (final MapEntry(key: id as String, value: hash as String)
        in index.entries) {
      ids.add(id);
      final stamp = File(p.join(dir.path, id, _stamp));
      if (await stamp.exists() && await stamp.readAsString() == hash) continue;
      final zip = await bundle.load('$_assets$id.zip');
      await _unpack(Uint8List.sublistView(zip), ids, stamp: hash);
    }
    return ids;
  }

  Future<Pack?> _read(Directory folder, Set<String> builtIn) async {
    final manifest = File(p.join(folder.path, _manifest));
    if (!await manifest.exists()) return null;
    final Pack? pack;
    try {
      pack = Pack.fromJson(jsonDecode(await manifest.readAsString()));
    } on FormatException {
      return null;
    }
    if (pack == null || pack.id != p.basename(folder.path)) return null;
    var bytes = 0;
    final files = <String>[];
    await for (final entry in folder.list(recursive: true)) {
      if (entry is! File) continue;
      bytes += await entry.length();
      final path = p.posix.joinAll(
        p.split(p.relative(entry.path, from: folder.path)),
      );
      if (path != _manifest && _kept.hasMatch(path)) files.add(path);
    }
    return pack.copyWith(
      builtIn: builtIn.contains(pack.id),
      bytes: bytes,
      files: files..sort(),
    );
  }

  /// Built-in packs first, then by name.
  Future<List<Pack>> list() async =>
      _installed(await (_builtIn ??= _unpackBundled()));

  Future<List<Pack>> _installed(Set<String> builtIn) async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    final packs = [
      await for (final entry in dir.list())
        if (entry is Directory && !p.basename(entry.path).startsWith('.'))
          ?await _read(entry, builtIn),
    ];
    return packs..sort(
      (a, b) => a.builtIn != b.builtIn
          ? (a.builtIn ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  /// Where pack [id] keeps [path]; null if it does not.
  Future<String?> pathOf(String id, String path) async {
    if (!Pack.validId(id) || !_kept.hasMatch(path)) return null;
    final file = File(p.joinAll([(await _dir()).path, id, ...path.split('/')]));
    return await file.exists() ? file.path : null;
  }

  /// The file a `pack:<id>/images/<name>` picture is; null if none.
  Future<String?> pictureAt(String picture) async {
    if (!isPackPicture(picture)) return null;
    final at = picture.indexOf('/');
    return pathOf(
      picture.substring(_picture.length, at),
      picture.substring(at + 1),
    );
  }

  Future<Uint8List?> read(Pack pack, String path) async =>
      switch (await pathOf(pack.id, path)) {
        final path? => File(path).readAsBytes(),
        null => null,
      };

  static bool _isFont(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final magic = String.fromCharCodes(bytes.take(4));
    return const {'\x00\x01\x00\x00', 'OTTO', 'true', 'ttcf'}.contains(magic);
  }

  /// Checks the zip in [bytes] and puts what it holds in place of any pack
  /// with its id. [stamp] marks it as a bundled pack's.
  Future<Pack> _unpack(
    Uint8List bytes,
    Set<String> builtIn, {
    String? stamp,
  }) async {
    final files = <String, Uint8List>{};
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const PackRefused(415, 'Not a zip file');
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String at(ArchiveFile file) =>
          p.posix.normalize(file.name.replaceAll(r'\', '/'));
      // A zip of the pack's folder has everything one level down.
      final manifests = [
        for (final file in archive)
          if (file.isFile && p.posix.basename(at(file)) == _manifest) at(file),
      ]..sort((a, b) => '/'.allMatches(a).length - '/'.allMatches(b).length);
      if (manifests.isEmpty) {
        throw const PackRefused(400, 'Not a pack: it has no $_manifest');
      }
      final root = manifests.first.substring(
        0,
        manifests.first.length - _manifest.length,
      );
      var total = 0;
      for (final file in archive) {
        if (!file.isFile || file.isSymbolicLink) continue;
        if (!at(file).startsWith(root)) continue;
        final path = at(file).substring(root.length);
        if (!_kept.hasMatch(path)) continue;
        total += file.size;
        if (total > maxBytes) throw const PackRefused(413, 'Pack too large');
        files[path] = file.readBytes() ?? Uint8List(0);
      }
      // A manifest can understate a file's size.
      if (files.values.fold(0, (sum, file) => sum + file.length) > maxBytes) {
        throw const PackRefused(413, 'Pack too large');
      }
    } on PackRefused {
      rethrow;
      // The decoder fails on a damaged zip in several ways, errors among them.
    } on Object {
      throw const PackRefused(415, 'Not a zip file');
    }

    final Pack? pack;
    try {
      pack = Pack.fromJson(jsonDecode(utf8.decode(files[_manifest]!)));
    } on FormatException {
      throw const PackRefused(400, '$_manifest is not JSON');
    }
    if (pack == null) {
      throw const PackRefused(
        400,
        '$_manifest needs an "id" of lower-case letters, digits, - or _',
      );
    }
    if (stamp == null && builtIn.contains(pack.id)) {
      throw PackRefused(409, '"${pack.id}" is built in');
    }
    final others = [
      for (final other in await _installed(builtIn))
        if (other.id != pack.id) ...other.iconSets,
    ];
    for (final MapEntry(key: path, value: content) in files.entries) {
      if (path.startsWith('fonts/') && !_isFont(content)) {
        throw PackRefused(415, '$path is not a TrueType or OpenType font');
      }
      if (!path.startsWith('icons/')) continue;
      final id = p.posix.basenameWithoutExtension(path);
      final IconSet? set;
      try {
        set = IconSet.fromJson(id, jsonDecode(utf8.decode(content)));
      } on FormatException {
        throw PackRefused(400, '$path is not JSON');
      }
      if (set == null) {
        throw PackRefused(400, '$path needs a "font" and its "icons"');
      }
      if (!files.containsKey('fonts/${set.font}')) {
        throw PackRefused(400, '$path names a font the pack does not have');
      }
      if (others.contains(id)) {
        throw PackRefused(409, 'Another pack already has icons called "$id"');
      }
    }
    try {
      PackContents.parse(pack.copyWith(builtIn: stamp != null), {
        for (final MapEntry(key: path, value: content) in files.entries)
          if (PackContents.reads(path))
            path: utf8.decode(content, allowMalformed: true),
      });
    } on FormatException catch (error) {
      throw PackRefused(400, error.message);
    }

    final dir = await _dir();
    final fresh = Directory(p.join(dir.path, '.${pack.id}.new'));
    if (await fresh.exists()) await fresh.delete(recursive: true);
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File(p.joinAll([fresh.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content);
    }
    if (stamp != null) {
      await File(p.join(fresh.path, _stamp)).writeAsString(stamp);
    }
    final home = Directory(p.join(dir.path, pack.id));
    if (await home.exists()) await home.delete(recursive: true);
    await fresh.rename(home.path);
    return pack;
  }

  /// Installs the zip in [body], replacing a pack with the same id.
  Future<Pack> install(Stream<List<int>> body) async {
    final zip = BytesBuilder(copy: false);
    await for (final chunk in body) {
      zip.add(chunk);
      if (zip.length > maxZipBytes) {
        throw const PackRefused(
          413,
          'File too large (${maxZipBytes ~/ (1024 * 1024)} MB max)',
        );
      }
    }
    final builtIn = await (_builtIn ??= _unpackBundled());
    final pack = await _unpack(zip.takeBytes(), builtIn);
    notifyListeners();
    return pack;
  }

  /// Removes pack [id] unless it is built in or the config names its icons.
  Future<void> delete(String id) async {
    final pack = (await list()).where((pack) => pack.id == id).firstOrNull;
    if (pack == null) throw const PackRefused(404, 'No such pack');
    if (pack.builtIn) throw PackRefused(409, '"${pack.name}" is built in');
    final config = await _ref.read(configProvider.future);
    final uses = pack.usesIn(config.toJson());
    if (uses > 0) {
      throw PackRefused(
        409,
        '"${pack.name}" is in use: $uses ${uses == 1 ? 'icon' : 'icons'}',
      );
    }
    await Directory(p.join((await _dir()).path, id)).delete(recursive: true);
    notifyListeners();
  }
}
