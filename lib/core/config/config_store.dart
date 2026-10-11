import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class ConfigStore {
  Future<LauncherConfig> load();
  Future<void> save(LauncherConfig config);
}

final configStoreProvider = Provider<ConfigStore>(
  (ref) => FileConfigStore(
    // Only inputs need device names; other ids describe themselves.
    device: () async => Device(
      names: {
        for (final input in await ref.read(tvInputsProvider.future))
          Entity.inputId(input.id): input.label,
      },
    ),
  ),
);

/// `config.json` in the app's support directory.
class FileConfigStore implements ConfigStore {
  FileConfigStore({this.device});

  /// Device info for migrations that use it. Waited on for at most 5 s.
  final Future<Device> Function()? device;

  Future<Device> _device() async {
    try {
      return await device?.call().timeout(const Duration(seconds: 5)) ??
          Device.unknown;
    } on Object catch (e) {
      debugPrint('Bringing the config up to date without the device: $e');
      return Device.unknown;
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'config.json'));
  }

  @override
  Future<LauncherConfig> load() async {
    final file = await _file();
    if (!await file.exists()) return LauncherConfig();
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final version = versionOf(json);
      if (version < oldestVersion) {
        // Too old to migrate: keep a copy and start fresh.
        await file.copy(p.join(file.parent.path, 'config.v$version.json'));
        return LauncherConfig();
      }
      final config = LauncherConfig.fromJson(
        json,
        device: needsDevice(json) ? await _device() : Device.unknown,
      );
      if (version < saveVersion) {
        // Save the migrated config at once, keeping the old file.
        await file.copy(p.join(file.parent.path, 'config.v$version.json'));
        await save(config);
      }
      return config;
    } on Object catch (e) {
      // Never fail on a bad file: keep it for inspection and use defaults.
      debugPrint('config.json unreadable, using defaults: $e');
      await file.copy('${file.path}.corrupt');
      return LauncherConfig();
    }
  }

  @override
  Future<void> save(LauncherConfig config) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(config.toJson()), flush: true);
    await tmp.rename(file.path);
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
