import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher_domain/layout/layout.dart';

final configProvider = AsyncNotifierProvider<ConfigController, LauncherConfig>(
  ConfigController.new,
);

/// The only place config is changed, so every change is saved and notified.
class ConfigController extends AsyncNotifier<LauncherConfig> {
  @override
  Future<LauncherConfig> build() => ref.watch(configStoreProvider).load();

  Future<void> _lastUpdate = Future.value();

  /// Changes run one after another, each reading what the one before left and
  /// finishing its save first; a failed change does not block the next.
  Future<void> _update(LauncherConfig Function(LauncherConfig) change) {
    final turn = _lastUpdate.catchError((Object _) {}).then((_) async {
      final next = change(await future);
      state = AsyncData(next);
      await ref.read(configStoreProvider).save(next);
    });
    _lastUpdate = turn;
    return turn;
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

  /// Sets the settings in [json], leaving the rest as it is.
  Future<void> patch(Map<String, Object?> json) =>
      _update((config) => config.patched(json));
}
