import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

/// Every prefab there is, by id: the launcher's own, and the user's, which
/// stand in for the launcher's where they have the same id.
final prefabsProvider = Provider<Map<String, Prefab>>((ref) {
  final own = ref.watch(
    configProvider.select((config) => config.value?.prefabs ?? const []),
  );
  return {
    for (final prefab in builtInPrefabs) prefab.id: prefab,
    for (final prefab in own) prefab.id: prefab,
  };
});

/// One part of an instance as it is drawn.
typedef InstancePart = ({
  String id,
  String kind,
  Map<String, Object?> options,
  bool hidden,
  PrefabSlot slot,
});

/// A prefab as one instance of it is drawn.
class PrefabInstance {
  const PrefabInstance(this.prefab, this.layoutName, this.layout, this.parts);

  final Prefab prefab;
  final String layoutName;
  final PrefabLayout layout;

  /// In the order the layout has them, those inside groups in their turn.
  final List<InstancePart> parts;

  /// The part in the place [slot], if the prefab has such a part.
  InstancePart? part(PrefabSlot slot) =>
      parts.where((part) => identical(part.slot, slot)).firstOrNull;

  /// What the instance does: the prefab's, but for each trigger [item] set
  /// itself.
  Triggers triggers(LayoutItem item) => {...prefab.on, ...item.on};
}

/// [prefab] as [item] shows it: each value is the instance's where it set
/// one, else the layout's, else the prefab's. Null for a prefab with no
/// way of being arranged.
PrefabInstance? instanceOf(Prefab prefab, LayoutItem item) {
  if (prefab.layouts.isEmpty) return null;
  final name = switch (item.options[layoutOption]) {
    final String name when prefab.layouts.containsKey(name) => name,
    _ => prefab.layouts.keys.first,
  };
  final layout = prefab.layouts[name]!;
  // Every place there is for a part, those inside groups among them.
  Iterable<PrefabSlot> places(PrefabLayout layout) => layout.slots.expand(
    (slot) => switch (slot.group) {
      null => [slot],
      final group => places(group),
    },
  );
  return PrefabInstance(prefab, name, layout, [
    for (final slot in places(layout))
      if (prefab.parts[slot.part] case final part?)
        () {
          final options = {
            ...part.options,
            ...slot.options,
            ...overridesOf(item, slot.part),
          };
          final hidden = options.remove(hiddenOption) == true;
          return (
            id: slot.part,
            kind: part.kind,
            options: options,
            hidden: hidden,
            slot: slot,
          );
        }(),
  ]);
}
