import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

/// All prefabs by id: built-in, then packs', then the user's, each
/// replacing the one before of the same id.
final prefabsProvider = Provider<Map<String, Prefab>>((ref) {
  final own = ref.watch(
    configProvider.select((config) => config.value?.prefabs ?? const []),
  );
  final packs = ref.watch(packContentsProvider).value ?? const [];
  return {
    for (final prefab in builtInPrefabs) prefab.id: prefab,
    for (final pack in packs)
      for (final prefab in pack.prefabs) prefab.id: prefab,
    for (final prefab in own) prefab.id: prefab,
  };
});
