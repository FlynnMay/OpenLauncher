import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/layout/layout.dart';

final configProvider = AsyncNotifierProvider<ConfigController, LauncherConfig>(
  ConfigController.new,
);

/// The only place config is mutated. The TV UI and the web server
/// both go through these methods, so every change is persisted and every
/// listener is notified the same way.
class ConfigController extends AsyncNotifier<LauncherConfig> {
  @override
  Future<LauncherConfig> build() => ref.watch(configStoreProvider).load();

  Future<void> _update(LauncherConfig Function(LauncherConfig) change) async {
    final next = change(await future);
    state = AsyncData(next);
    await ref.read(configStoreProvider).save(next);
  }

  /// Replaces where everything is. [layout] is made valid first.
  Future<void> setLayout(Layout layout) =>
      _update((c) => c.copyWith(layout: layout.normalised()));

  /// Changes the config in whatever way [how] says. For a setting that is
  /// plain data this is all there is to changing it:
  /// `change((c) => c.copyWith(toasts: ...))`.
  Future<void> change(LauncherConfig Function(LauncherConfig config) how) =>
      _update(how);

  /// Sets the parts of the config [json] names, as they are saved; see
  /// [LauncherConfig.openKeys] for which there are.
  Future<void> patch(Map<String, Object?> json) =>
      _update((c) => c.patched(json));

  /// Takes a card off every panel. It stays off until it is placed again.
  Future<void> removeCard(String id) =>
      _update((c) => c.copyWith(layout: c.layout.without({id}).normalised()));

  /// Sets the images and videos behind the home screen, the first being
  /// the one shown unless they take turns; none leaves it plain.
  Future<void> setWallpapers(List<String> paths) =>
      _update((c) => c.copyWith(wallpapers: List.unmodifiable(paths)));

  /// Sets how many minutes each wallpaper stays; 0 keeps to the first.
  Future<void> setWallpaperEvery(int minutes) => _update(
    (c) => c.copyWith(
      wallpaperEvery: minutes.clamp(0, LauncherConfig.maxWallpaperEvery),
    ),
  );

  /// Sets a custom image for a card; pass null to return to the automatic one.
  /// Either way the card stops showing another card's picture.
  Future<void> setIconOverride(String id, String? path) => _update(
    (c) => c.copyWith(
      iconOverrides: path == null
          ? ({...c.iconOverrides}..remove(id))
          : {...c.iconOverrides, id: path},
      iconSources: {...c.iconSources}..remove(id),
    ),
  );

  /// Makes card [id] show the picture of card [from]; null gives it its own
  /// back.
  Future<void> setIconSource(String id, String? from) => _update(
    (c) => c.copyWith(
      iconSources: from == null
          ? ({...c.iconSources}..remove(id))
          : {...c.iconSources, id: from},
    ),
  );

  /// Names a card; null or blank returns it to the name the device gives it.
  Future<void> setName(String id, String? name) {
    final trimmed = name?.trim() ?? '';
    return _update(
      (c) => c.copyWith(
        names: trimmed.isEmpty
            ? ({...c.names}..remove(id))
            : {...c.names, id: trimmed},
      ),
    );
  }
}
