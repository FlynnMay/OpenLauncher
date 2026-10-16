import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/layout/layout.dart';

final configProvider = AsyncNotifierProvider<ConfigController, LauncherConfig>(
  ConfigController.new,
);

/// The only place config is changed, so every change is saved and notified.
class ConfigController extends AsyncNotifier<LauncherConfig> {
  @override
  Future<LauncherConfig> build() => ref.watch(configStoreProvider).load();

  Future<void> _update(LauncherConfig Function(LauncherConfig) change) async {
    final next = change(await future);
    state = AsyncData(next);
    await ref.read(configStoreProvider).save(next);
  }

  /// Replaces the layout, repaired first. The pictures of folders it no
  /// longer has go with them.
  Future<void> setLayout(Layout layout) =>
      _update((c) => _withLayout(c, layout.normalised()));

  /// Puts back the starting layout as its pack has it.
  Future<void> revertLayout() async {
    final start = await ref.read(startingLayoutProvider.future);
    await _update((c) => _withLayout(c, start, own: false));
  }

  static LauncherConfig _withLayout(
    LauncherConfig c,
    Layout next, {
    bool own = true,
  }) {
    final folders = {for (final pane in next.docked) Layout.iconKey(pane.id)};
    return c.copyWith(
      layout: next,
      ownLayout: own,
      iconOverrides: {
        for (final MapEntry(:key, :value) in c.iconOverrides.entries)
          if (!key.startsWith(Layout.iconKey('')) || folders.contains(key))
            key: value,
      },
    );
  }

  /// Applies [how] to the config.
  Future<void> change(LauncherConfig Function(LauncherConfig config) how) =>
      _update(how);

  /// Sets the [LauncherConfig.openKeys] parts present in [json].
  Future<void> patch(Map<String, Object?> json) =>
      _update((c) => c.patched(json));

  /// Removes an entity from [layer], or from every layer, until it is placed
  /// again.
  Future<void> removeEntity(String id, {String? layer}) => _update(
    (c) =>
        c.copyWith(layout: c.layout.without({id}, layer: layer).normalised()),
  );

  /// Adds [item] to pane [pane].
  Future<void> addItem(Component item, String pane) => _update(
    (c) => c.copyWith(layout: c.layout.withAdded(item, pane).normalised()),
  );

  Future<void> setWallpapers(List<String> paths) =>
      _update((c) => c.copyWith(wallpapers: List.unmodifiable(paths)));

  /// Minutes per wallpaper; 0 stays on the first.
  Future<void> setWallpaperEvery(int minutes) => _update(
    (c) => c.copyWith(
      wallpaperEvery: minutes.clamp(0, LauncherConfig.maxWallpaperEvery),
    ),
  );

  /// Sets a custom picture; null restores the automatic one. Clears any
  /// borrowed picture.
  Future<void> setIconOverride(String id, String? path) => _update(
    (c) => c.copyWith(
      iconOverrides: path == null
          ? ({...c.iconOverrides}..remove(id))
          : {...c.iconOverrides, id: path},
      iconSources: {...c.iconSources}..remove(id),
    ),
  );

  /// Makes [id] show [from]'s picture, in place of a custom one; null
  /// restores its own.
  Future<void> setIconSource(String id, String? from) => _update(
    (c) => c.copyWith(
      iconSources: from == null
          ? ({...c.iconSources}..remove(id))
          : {...c.iconSources, id: from},
      iconOverrides: from == null
          ? c.iconOverrides
          : ({...c.iconOverrides}..remove(id)),
    ),
  );

  /// Renames an entity; null or blank restores the device's name.
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
