import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_kinds.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Installed apps as reported by the device, refreshed on package changes.
final installedAppsProvider =
    AsyncNotifierProvider<InstalledAppsNotifier, List<InstalledApp>>(
      InstalledAppsNotifier.new,
    );

/// The TV's own inputs (HDMI ports, tuner); empty on devices without any.
final tvInputsProvider = AsyncNotifierProvider<TvInputsNotifier, List<TvInput>>(
  TvInputsNotifier.new,
);

/// A list read from the device that is re-read whenever the device says it
/// changed.
abstract class _DeviceListNotifier<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> load(LauncherPlatform platform);
  Stream<void> changes(LauncherPlatform platform);

  int _generation = 0;

  @override
  Future<List<T>> build() {
    final platform = ref.watch(launcherPlatformProvider);
    // The subscription lives as long as the provider, so no change event is
    // missed while a refresh is in flight.
    final sub = changes(platform).listen((_) => _refresh(platform));
    ref.onDispose(sub.cancel);
    return load(platform);
  }

  Future<void> _refresh(LauncherPlatform platform) async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(() => load(platform));
    // Changes arrive in bursts; only the newest query may publish.
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

/// Every entity there is, of every kind, removed ones included, with the
/// user's pictures and names applied: kind by kind in the order the kinds
/// are listed, each alphabetically. Where they are shown is up to the
/// layout.
final entitiesProvider = FutureProvider<List<Entity>>((ref) async {
  final config = await ref.watch(configProvider.future);
  return arrangeEntities([
    for (final kind in entityKinds) ...await kind.list(ref),
  ], config);
});

/// Swaps in the user's pictures and names and sorts the entities the device
/// offers: inputs before apps, each alphabetically.
List<Entity> arrangeEntities(List<Entity> available, LauncherConfig config) {
  final pictured = {
    for (final entity in available)
      entity.id: switch (config.iconOverrides[entity.id]) {
        null => entity,
        // Custom art is assumed to be drawn for the full entity.
        final path => Entity(
          id: entity.id,
          kind: entity.kind,
          target: entity.target,
          label: entity.label,
          iconPath: path,
          wideIcon: true,
        ),
      },
  };
  final entities = [
    for (var entity in pictured.values)
      () {
        // The other entity's picture as it would show by itself: an entity that
        // borrows in turn is not followed, so there are no chains or loops.
        // An entity whose source is gone keeps its own until it is back.
        if (pictured[config.iconSources[entity.id]] case final source?) {
          entity = entity.withPictureOf(source);
        }
        if (config.names[entity.id] case final name?) {
          entity = entity.withLabel(name);
        }
        return entity;
      }(),
  ];
  entities.sort((a, b) {
    if (a.kind != b.kind) {
      return entityKindIndex(a.kind).compareTo(entityKindIndex(b.kind));
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return entities;
}
