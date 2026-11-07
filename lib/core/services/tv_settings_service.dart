import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// The TV's own settings.
class TvSettingsService {
  TvSettingsService(this._ref);

  final Ref _ref;

  Future<String?> open() async {
    await _ref.read(launcherPlatformProvider).openTvSettings();
    return null;
  }
}

final tvSettingsServiceProvider = Provider<TvSettingsService>(
  TvSettingsService.new,
);
