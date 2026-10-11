import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_registry.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

final installedAppsProvider =
    AsyncNotifierProvider<InstalledAppsNotifier, List<InstalledApp>>(
      InstalledAppsNotifier.new,
    );

/// The TV's inputs (HDMI ports, tuner).
final tvInputsProvider = AsyncNotifierProvider<TvInputsNotifier, List<TvInput>>(
  TvInputsNotifier.new,
);

/// A device list that reloads when the device reports a change.
abstract class _DeviceListNotifier<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> load(LauncherPlatform platform);
  Stream<void> changes(LauncherPlatform platform);

  int _generation = 0;

  @override
  Future<List<T>> build() {
    final platform = ref.watch(launcherPlatformProvider);
    // Subscribed for the provider's lifetime so no change is missed.
    final sub = changes(platform).listen((_) => _refresh(platform));
    ref.onDispose(sub.cancel);
    return load(platform);
  }

  Future<void> _refresh(LauncherPlatform platform) async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(() => load(platform));
    // Only the newest of a burst of reloads publishes.
    if (ref.mounted && generation == _generation) state = next;
  }
}

class InstalledAppsNotifier extends _DeviceListNotifier<InstalledApp> {
  @override
  Future<List<InstalledApp>> load(LauncherPlatform platform) =>
      platform.listApps();

  @override
  Stream<void> changes(LauncherPlatform platform) => platform.appsChanged;
}

class TvInputsNotifier extends _DeviceListNotifier<TvInput> {
  @override
  Future<List<TvInput>> load(LauncherPlatform platform) =>
      platform.listInputs();

  @override
  Stream<void> changes(LauncherPlatform platform) => platform.inputsChanged;
}

/// Every entity of every category, with the user's names and pictures
/// applied, sorted by category then label.
final entitiesProvider = FutureProvider<List<Entity>>((ref) async {
  final config = await ref.watch(configProvider.future);
  return arrangeEntities([
    for (final kind in entityRegistries) ...await kind.list(ref),
  ], config);
});

/// Applies the user's pictures and names, then sorts.
List<Entity> arrangeEntities(List<Entity> available, LauncherConfig config) {
  final pictured = {
    for (final entity in available)
      entity.id: switch (config.iconOverrides[entity.id]) {
        null => entity,
        // Custom art is treated as full-frame.
        final path => entity.withData({
          Entity.icon: path,
          Entity.shape: Entity.banner,
        }),
      },
  };
  final entities = [
    for (var entity in pictured.values)
      () {
        // Borrowing is one level deep, so no chains or loops.
        if (pictured[config.iconSources[entity.id]] case final source?) {
          entity = entity.withData({
            Entity.icon: source.data[Entity.icon],
            Entity.shape: source.data[Entity.shape],
          });
        }
        if (config.names[entity.id] case final name?) {
          entity = entity.withLabel(name);
        }
        return entity;
      }(),
  ];
  entities.sort((a, b) {
    if (a.category != b.category) {
      return entityRegistryIndex(a.category)
          .compareTo(entityRegistryIndex(b.category));
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return entities;
}
