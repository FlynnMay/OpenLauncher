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

  Future<void> setLayout(Layout layout) =>
      _update((config) => _withLayout(config, layout.normalised()));

  Future<void> revertLayout() async {
    final start = await ref.read(startingLayoutProvider.future);
    await _update(
      (config) => _withLayout(config, start.layout, ownLayout: false),
    );
  }

  static LauncherConfig _withLayout(
    LauncherConfig config,
    Layout layout, {
    bool ownLayout = true,
  }) {
    return config.copyWith(
      layout: layout,
      ownLayout: ownLayout,
      iconOverrides: _withoutRemovedNodePictures(config.iconOverrides, layout),
    );
  }

  static Map<String, String> _withoutRemovedNodePictures(
    Map<String, String> pictures,
    Layout layout,
  ) {
    final nodePictures = {
      for (final node in layout.all) Layout.pictureKey(node.id),
    };
    bool kept(String key) =>
        !key.startsWith(Layout.pictureKey('')) || nodePictures.contains(key);
    return {
      for (final MapEntry(:key, :value) in pictures.entries)
        if (kept(key)) key: value,
    };
  }

  Future<void> change(LauncherConfig Function(LauncherConfig config) how) =>
      _update(how);

  Future<void> patch(Map<String, Object?> json) =>
      _update((config) => config.patched(json));

  Future<void> setWallpapers(List<String> paths) => _update(
    (config) => config.copyWith(wallpapers: List.unmodifiable(paths)),
  );

  Future<void> setWallpaperEvery(int minutes) => _update(
    (config) => config.copyWith(
      wallpaperEvery: minutes.clamp(0, LauncherConfig.maxWallpaperEvery),
    ),
  );

  Future<void> setIconOverride(String id, String? path) => _update(
    (config) => config.copyWith(
      iconOverrides: path == null
          ? ({...config.iconOverrides}..remove(id))
          : {...config.iconOverrides, id: path},
      iconSources: {...config.iconSources}..remove(id),
    ),
  );

  Future<void> setIconSource(String id, String? from) => _update(
    (config) => config.copyWith(
      iconSources: from == null
          ? ({...config.iconSources}..remove(id))
          : {...config.iconSources, id: from},
      iconOverrides: from == null
          ? config.iconOverrides
          : ({...config.iconOverrides}..remove(id)),
    ),
  );

  Future<void> setName(String id, String? name) {
    final trimmed = name?.trim() ?? '';
    return _update(
      (config) => config.copyWith(
        names: trimmed.isEmpty
            ? ({...config.names}..remove(id))
            : {...config.names, id: trimmed},
      ),
    );
  }
}
