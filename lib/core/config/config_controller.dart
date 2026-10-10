import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_store.dart';
import 'launcher_config.dart';

final configProvider = AsyncNotifierProvider<ConfigController, LauncherConfig>(
  ConfigController.new,
);

/// The only place config is mutated. The TV UI and (later) the web server
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

  /// Sets the full display order, as the ids of the cards in sequence.
  Future<void> setOrder(List<String> ids) =>
      _update((c) => c.copyWith(order: List.unmodifiable(ids)));

  Future<void> setHidden(String id, bool hidden) => _update(
    (c) => c.copyWith(
      hidden: hidden ? {...c.hidden, id} : ({...c.hidden}..remove(id)),
    ),
  );

  /// Sets the image or video behind the home screen; null removes it.
  Future<void> setWallpaper(String? path) =>
      _update((c) => c.copyWith(wallpaper: path));

  /// Sets a custom image for a card; pass null to return to the automatic one.
  Future<void> setIconOverride(String id, String? path) => _update(
    (c) => c.copyWith(
      iconOverrides: path == null
          ? ({...c.iconOverrides}..remove(id))
          : {...c.iconOverrides, id: path},
    ),
  );
}
