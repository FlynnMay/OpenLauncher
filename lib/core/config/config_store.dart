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

final startingLayoutProvider = FutureProvider<({String? id, Layout layout})>((
  ref,
) async {
  try {
    for (final pack in await ref.watch(packContentsProvider.future)) {
      if (pack.starting case final layout?) {
        return (id: pack.start, layout: layout);
      }
    }
  } on Object catch (error) {
    debugPrint('Packs unreadable, starting from a blank layout: $error');
  }
  return (id: null, layout: Layout.blank());
});

final configStoreProvider = Provider<ConfigStore>(
  (ref) => FileConfigStore(
    startingLayout: () async =>
        (await ref.read(startingLayoutProvider.future)).layout,
  ),
);

class FileConfigStore implements ConfigStore {
  FileConfigStore({
    this.device,
    this.startingLayout,
    Future<Directory> Function()? dir,
  }) : _directory = dir ?? getApplicationSupportDirectory;

  final Future<Layout> Function()? startingLayout;
  final Future<Device> Function()? device;
  final Future<Directory> Function() _directory;
  final _lastWritten = <String, String>{};

  Future<Device> _device() async {
    try {
      return await device?.call().timeout(const Duration(seconds: 5)) ??
          Device.unknown;
    } on Object catch (error) {
      debugPrint('Bringing the config up to date without the device: $error');
      return Device.unknown;
    }
  }

  static String _fileName(String id) => '${Uri.encodeComponent(id)}.json';

  @override
  Future<LauncherConfig> load() async {
    final config = await _read();
    if (config.ownLayout || startingLayout == null) return config;
    return config.copyWith(layout: await startingLayout!(), ownLayout: false);
  }

  Future<LauncherConfig> _read() async {
    final directory = await _directory();
    final file = File(p.join(directory.path, 'config.json'));
    if (!await file.exists()) return LauncherConfig();
    final Json json;
    try {
      json = await _withPartsRead(
        jsonDecode(await file.readAsString()) as Json,
        directory,
      );
    } on Object catch (error) {
      return _defaultsKeeping(file, error);
    }
    final version = versionOf(json);
    Future<void> keepUnmigratedCopy() =>
        File(p.join(directory.path, 'config.v$version.json'))
            .writeAsString(jsonEncode(json));
    if (isNewer(json)) {
      await keepUnmigratedCopy();
      return LauncherConfig();
    }
    try {
      final config = LauncherConfig.fromJson(
        json,
        device: needsDevice(json) ? await _device() : Device.unknown,
      );
      if (version < saveVersion) {
        await keepUnmigratedCopy();
        await save(config);
      } else if (_isOldSingleFile(json)) {
        await save(config);
      }
      return config;
    } on Object catch (error) {
      return _defaultsKeeping(file, error);
    }
  }

  Future<LauncherConfig> _defaultsKeeping(File unreadable, Object error) async {
    debugPrint('config.json unreadable, using defaults: $error');
    await _keepCorrupt(unreadable);
    return LauncherConfig();
  }

  static Future<void> _keepCorrupt(File file) =>
      file.copy('${file.path}.corrupt');

  static bool _isOldSingleFile(Json json) => [
    if (json['layout'] case {'screens': final List<Object?> screens})
      ...screens,
    ...?json['prefabs'] as List<Object?>?,
    ...?json['entities'] as List<Object?>?,
  ].any((part) => part is! String);

  Future<Json> _withPartsRead(Json json, Directory directory) async => {
    ...json,
    if (json['layout'] case final Json layout)
      'layout': {
        ...layout,
        'screens': await _readParts(directory, 'screens', layout['screens']),
      },
    if (json.containsKey('prefabs'))
      'prefabs': await _readParts(directory, 'prefabs', json['prefabs']),
    if (json.containsKey('entities'))
      'entities': await _readParts(directory, 'entities', json['entities']),
  };

  Future<Object?> _readParts(
    Directory directory,
    String folder,
    Object? parts,
  ) async {
    if (parts is! List<Object?>) return parts;
    return [
      for (final part in parts)
        if (part is String) ?await _readPart(directory, folder, part) else part,
    ];
  }

  Future<Object?> _readPart(
    Directory directory,
    String folder,
    String id,
  ) async {
    final file = File(p.join(directory.path, folder, _fileName(id)));
    try {
      return jsonDecode(await file.readAsString());
    } on Object catch (error) {
      debugPrint('$folder/${_fileName(id)} unreadable, left out: $error');
      if (await file.exists()) await _keepCorrupt(file);
      return null;
    }
  }

  @override
  Future<void> save(LauncherConfig config) async {
    final directory = await _directory();
    final json = config.toJson();
    final layout = json['layout'];
    final ids = {
      'screens': await _writeParts(
        directory,
        'screens',
        layout is Json ? layout['screens'] : null,
      ),
      'prefabs': await _writeParts(directory, 'prefabs', json['prefabs']),
      'entities': await _writeParts(directory, 'entities', json['entities']),
    };
    if (layout is Json) json['layout'] = {...layout, 'screens': ids['screens']};
    json['prefabs'] = ids['prefabs'];
    json['entities'] = ids['entities'];
    await _writeIfChanged(File(p.join(directory.path, 'config.json')), json);
    for (final MapEntry(key: folder, value: listed) in ids.entries) {
      await _removeUnlisted(
        Directory(p.join(directory.path, folder)),
        listed.map(_fileName).toSet(),
      );
    }
  }

  Future<List<String>> _writeParts(
    Directory directory,
    String folder,
    Object? parts,
  ) async {
    final ids = <String>[];
    for (final part in parts is List<Object?> ? parts : const <Object?>[]) {
      if (part case {'id': final String id}) {
        ids.add(id);
        await _writeIfChanged(
          File(p.join(directory.path, folder, _fileName(id))),
          part,
        );
      }
    }
    return ids;
  }

  Future<void> _removeUnlisted(Directory folder, Set<String> fileNames) async {
    if (!await folder.exists()) return;
    await for (final entry in folder.list()) {
      final name = p.basename(entry.path);
      if (entry is File &&
          name.endsWith('.json') &&
          !fileNames.contains(name)) {
        await entry.delete();
        _lastWritten.remove(entry.path);
      }
    }
  }

  Future<void> _writeIfChanged(File file, Object? json) async {
    final text = jsonEncode(json);
    if (_lastWritten[file.path] == text) return;
    await _writeWholeOrNothing(file, text);
    _lastWritten[file.path] = text;
  }

  static Future<void> _writeWholeOrNothing(File file, String text) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
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
