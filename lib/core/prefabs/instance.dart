import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

/// All prefabs by id; the user's replace built-ins of the same id.
final prefabsProvider = Provider<Map<String, Prefab>>((ref) {
  final own = ref.watch(
    configProvider.select((config) => config.value?.prefabs ?? const []),
  );
  return {
    for (final prefab in builtInPrefabs) prefab.id: prefab,
    for (final prefab in own) prefab.id: prefab,
  };
});
