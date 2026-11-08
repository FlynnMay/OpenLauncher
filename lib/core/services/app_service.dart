import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What can be done to an installed app, named by its package.
class AppService {
  AppService(this._ref);

  final Ref _ref;

  LauncherPlatform get _platform => _ref.read(launcherPlatformProvider);

  Future<String?> launch(String package) async {
    await _platform.launchApp(package);
    return null;
  }

  Future<String?> showInfo(String package) async {
    await _platform.openAppInfo(package);
    return null;
  }

  Future<String?> uninstall(String package) async {
    await _platform.uninstallApp(package);
    return null;
  }
}

final appServiceProvider = Provider<AppService>(AppService.new);
