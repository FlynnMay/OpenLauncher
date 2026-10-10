import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'launcher_config.dart';

/// Where [LauncherConfig] is persisted.
abstract class ConfigStore {
  Future<LauncherConfig> load();
  Future<void> save(LauncherConfig config);
}

final configStoreProvider = Provider<ConfigStore>((ref) => FileConfigStore());

/// Stores the config as `config.json` in the app's support directory.
class FileConfigStore implements ConfigStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'config.json'));
  }

  @override
  Future<LauncherConfig> load() async {
    final file = await _file();
    if (!await file.exists()) return const LauncherConfig();
    try {
      final json = jsonDecode(await file.readAsString());
      return LauncherConfig.fromJson(json as Map<String, dynamic>);
    } on Object catch (e) {
      // An unreadable file must not brick the home screen; keep it for
      // inspection and start from defaults.
      debugPrint('config.json unreadable, using defaults: $e');
      await file.copy('${file.path}.corrupt');
      return const LauncherConfig();
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
  MemoryConfigStore([this.config = const LauncherConfig()]);

  LauncherConfig config;

  @override
  Future<LauncherConfig> load() async => config;

  @override
  Future<void> save(LauncherConfig config) async => this.config = config;
}
