import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity_generators.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher_domain/entities/entity.dart';

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

/// The entity registry: every entity there is, with the user's names and
/// pictures applied, sorted by category then label.
final entitiesProvider = FutureProvider<List<Entity>>((ref) async {
  // Every watch before any wait: none may follow a rebuild.
  final config = ref.watch(configProvider.future);
  final packs = ref.watch(packsProvider.future);
  final generated = Future.wait([
    for (final generate in entityGenerators) generate(ref),
  ]);
  return arrangeEntities(
    _firstWithEachId(await generated),
    await config,
    order: Pack.categoriesOf(await packs).keys,
  );
});

List<Entity> _firstWithEachId(List<List<Entity>> generated) {
  final known = <String>{};
  return [
    for (final entity in generated.expand((entities) => entities))
      if (known.add(entity.id)) entity,
  ];
}

/// Applies the user's pictures and names, then sorts: by category, those in
/// [order] first, then by label.
List<Entity> arrangeEntities(
  List<Entity> available,
  LauncherConfig config, {
  Iterable<String> order = const [],
}) {
  final pictured = _withCustomPictures(available, config);
  final entities = [
    for (final entity in pictured.values)
      _withBorrowedPicture(_withName(entity, config), pictured, config),
  ];
  _sortByCategoryThenLabel(entities, available, order);
  return entities;
}

Map<String, Entity> _withCustomPictures(
  List<Entity> available,
  LauncherConfig config,
) => {
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

Entity _withName(Entity entity, LauncherConfig config) =>
    switch (config.names[entity.id]) {
      final name? => entity.withLabel(name),
      null => entity,
    };

/// Borrowing is one level deep, so no chains or loops.
Entity _withBorrowedPicture(
  Entity entity,
  Map<String, Entity> pictured,
  LauncherConfig config,
) => switch (pictured[config.iconSources[entity.id]]) {
  final source? => entity.withData({
    Entity.icon: source.data[Entity.icon],
    Entity.shape: source.data[Entity.shape],
  }),
  null => entity,
};

/// Categories in [order], then as they first come.
void _sortByCategoryThenLabel(
  List<Entity> entities,
  List<Entity> available,
  Iterable<String> order,
) {
  final categories = {
    ...order,
    for (final entity in available) entity.category,
  }.toList();
  entities.sort((a, b) {
    if (a.category != b.category) {
      return categories
          .indexOf(a.category)
          .compareTo(categories.indexOf(b.category));
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
}
