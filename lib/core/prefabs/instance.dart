import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

/// The prefabs packs ship, by id; the launcher's own are the System pack's.
final shippedPrefabsProvider = Provider<Map<String, Prefab>>(
  (ref) => {
    for (final pack in ref.watch(packContentsProvider).value ?? const [])
      for (final prefab in pack.prefabs) prefab.id: prefab,
  },
);

/// All prefabs by id: the packs', then the user's, which replace any of the
/// same id.
final prefabsProvider = Provider<Map<String, Prefab>>((ref) {
  final own = ref.watch(
    configProvider.select((config) => config.value?.prefabs ?? const []),
  );
  return {
    ...ref.watch(shippedPrefabsProvider),
    for (final prefab in own) prefab.id: prefab,
  };
});
