import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class ConfigStore {
  Future<LauncherConfig> load();
  Future<void> save(LauncherConfig config);
}

/// The layout a new home screen starts as: the first a pack marks to start
/// with, by id; blank if none does.
final startingLayoutProvider = FutureProvider<({String? id, Layout layout})>((
  ref,
) async {
  try {
    for (final pack in await ref.watch(packContentsProvider.future)) {
      if (pack.starting case final layout?) {
        return (id: pack.start, layout: layout);
      }
    }
  } on Object catch (e) {
    debugPrint('Packs unreadable, starting from a blank layout: $e');
  }
  return (id: null, layout: Layout.blank());
});

final configStoreProvider = Provider<ConfigStore>(
  (ref) => FileConfigStore(
    starting: () async =>
        (await ref.read(startingLayoutProvider.future)).layout,
  ),
);

/// `config.json` in the app's support directory, with each screen, prefab
/// and entity of the user's in a file of its own under `screens/`,
/// `prefabs/` and `entities/`, as a pack keeps them; `config.json` lists
/// them by id, in order. Without a layout of the user's it has the
/// [starting] one.
class FileConfigStore implements ConfigStore {
  FileConfigStore({
    this.device,
    this.starting,
    Future<Directory> Function()? dir,
  }) : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Layout> Function()? starting;

  /// Device info for migrations that use it. Waited on for at most 5 s.
  final Future<Device> Function()? device;

  final Future<Directory> Function() _dir;

  /// Text last written, by path, so what has not changed is not written
  /// again.
  final _written = <String, String>{};

  static const _folders = ['screens', 'prefabs', 'entities'];

  Future<Device> _device() async {
    try {
      return await device?.call().timeout(const Duration(seconds: 5)) ??
          Device.unknown;
    } on Object catch (e) {
      debugPrint('Bringing the config up to date without the device: $e');
      return Device.unknown;
    }
  }

  static String _name(String id) => '${Uri.encodeComponent(id)}.json';

  @override
  Future<LauncherConfig> load() async {
    final config = await _read();
    if (config.ownLayout || starting == null) return config;
    return config.copyWith(layout: await starting!(), ownLayout: false);
  }

  Future<LauncherConfig> _read() async {
    final dir = await _dir();
    final file = File(p.join(dir.path, 'config.json'));
    if (!await file.exists()) return LauncherConfig();
    final Map<String, dynamic> json;
    try {
      json = await _whole(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        dir,
      );
    } on Object catch (e) {
      // Never fail on a bad file: keep it for inspection and use defaults.
      debugPrint('config.json unreadable, using defaults: $e');
      await file.copy('${file.path}.corrupt');
      return LauncherConfig();
    }
    final version = versionOf(json);
    // A copy of what was read, whole, before it is changed.
    Future<void> keep() =>
        File(p.join(dir.path, 'config.v$version.json'))
            .writeAsString(jsonEncode(json));
    if (isNewer(json)) {
      // From a newer release: keep a copy and start fresh.
      await keep();
      return LauncherConfig();
    }
    try {
      final config = LauncherConfig.fromJson(
        json,
        device: needsDevice(json) ? await _device() : Device.unknown,
      );
      if (version < saveVersion) {
        // Save the migrated config at once, keeping the old one.
        await keep();
        await save(config);
      } else if (_inline(json)) {
        await save(config);
      }
      return config;
    } on Object catch (e) {
      debugPrint('config.json unreadable, using defaults: $e');
      await file.copy('${file.path}.corrupt');
      return LauncherConfig();
    }
  }

  /// Whether [json] holds screens, prefabs or entities itself, as one file
  /// did before they had their own.
  static bool _inline(Map<String, dynamic> json) => [
    if (json['layout'] case {'screens': final List<Object?> screens})
      ...screens,
    ...?json['prefabs'] as List<Object?>?,
    ...?json['entities'] as List<Object?>?,
  ].any((part) => part is! String);

  /// [json] with the screens, prefabs and entities it names by id read from
  /// their files. One whose file cannot be read is left out, the file kept.
  Future<Map<String, dynamic>> _whole(
    Map<String, dynamic> json,
    Directory dir,
  ) async {
    Future<Object?> read(String folder, Object? parts) async {
      if (parts is! List<Object?>) return parts;
      return [
        for (final part in parts)
          if (part is String) ?await _part(dir, folder, part) else part,
      ];
    }

    return {
      ...json,
      if (json['layout'] case final Map<String, dynamic> layout)
        'layout': {
          ...layout,
          'screens': await read('screens', layout['screens']),
        },
      if (json.containsKey('prefabs'))
        'prefabs': await read('prefabs', json['prefabs']),
      if (json.containsKey('entities'))
        'entities': await read('entities', json['entities']),
    };
  }

  Future<Object?> _part(Directory dir, String folder, String id) async {
    final file = File(p.join(dir.path, folder, _name(id)));
    try {
      return jsonDecode(await file.readAsString());
    } on Object catch (e) {
      debugPrint('$folder/${_name(id)} unreadable, left out: $e');
      if (await file.exists()) await file.copy('${file.path}.corrupt');
      return null;
    }
  }

  @override
  Future<void> save(LauncherConfig config) async {
    final dir = await _dir();
    final json = config.toJson();
    final names = {for (final folder in _folders) folder: <String>{}};
    // Each part to its file; the ids, in order, in its place.
    Future<List<String>> split(String folder, Object? parts) async {
      final ids = <String>[];
      for (final part in parts is List<Object?> ? parts : const <Object?>[]) {
        if (part case {'id': final String id}) {
          ids.add(id);
          names[folder]!.add(_name(id));
          await _write(File(p.join(dir.path, folder, _name(id))), part);
        }
      }
      return ids;
    }

    if (json['layout'] case final Map<String, dynamic> layout) {
      json['layout'] = {
        ...layout,
        'screens': await split('screens', layout['screens']),
      };
    }
    json['prefabs'] = await split('prefabs', json['prefabs']);
    json['entities'] = await split('entities', json['entities']);
    await _write(File(p.join(dir.path, 'config.json')), json);
    // What is no longer listed goes.
    for (final MapEntry(key: folder, value: kept) in names.entries) {
      final folderDir = Directory(p.join(dir.path, folder));
      if (!await folderDir.exists()) continue;
      await for (final entry in folderDir.list()) {
        final name = p.basename(entry.path);
        if (entry is File && name.endsWith('.json') && !kept.contains(name)) {
          await entry.delete();
          _written.remove(entry.path);
        }
      }
    }
  }

  /// Writes [json] to [file] whole or not at all, unless it holds it already.
  Future<void> _write(File file, Object? json) async {
    final text = jsonEncode(json);
    if (_written[file.path] == text) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
    _written[file.path] = text;
  }
}

class MemoryConfigStore implements ConfigStore {
  MemoryConfigStore([LauncherConfig? config])
    : config = config ?? LauncherConfig();

  LauncherConfig config;

  @override
  Future<LauncherConfig> load() async => config;

  @override
  Future<void> save(LauncherConfig config) async => this.config = config;
}
