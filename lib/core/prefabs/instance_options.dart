import 'package:openlauncher/core/layout/layout_item.dart';

/// The prefab an entity is an instance of unless it names another, and the
/// one an entity that opens a folder is.
const cardPrefabId = 'app-card';
const folderPrefabId = 'folder-card';

// What an instance says of itself is kept in its item's options, under
// these names: which prefab, which of its layouts, and, by part, the
// values it sets differently (`hidden` among them).
const layoutOption = 'layout';
const partsOption = 'parts';

/// Set for a part an instance does not show.
const hiddenOption = 'hidden';

/// The id of the prefab [item] is an instance of.
String prefabIdOf(LayoutItem item) => item.ref;

/// [options] as they are under [rule], which a pane sets for every
/// instance of a prefab in it: its layout, and whatever it says of a part,
/// count over what the instance says for itself.
Map<String, Object?> underRule(
  Map<String, Object?> options,
  Map<String, Object?> rule,
) {
  var next = {...options, layoutOption: ?rule[layoutOption]};
  if (rule[partsOption] case final Map<Object?, Object?> parts) {
    for (final MapEntry(:key, :value) in parts.entries) {
      if (key is String && value is Map<Object?, Object?>) {
        next = withOverrides(next, key, value.cast());
      }
    }
  }
  return next;
}

/// What [item] sets differently about the part [part].
Map<String, Object?> overridesOf(LayoutItem item, String part) =>
    switch (item.options[partsOption]) {
      final Map<Object?, Object?> parts => switch (parts[part]) {
        final Map<Object?, Object?> set => set.cast(),
        _ => const {},
      },
      _ => const {},
    };

/// [options] with [values] set for the part [part]; a value of null is
/// taken away, which hands that value back to the prefab.
Map<String, Object?> withOverrides(
  Map<String, Object?> options,
  String part,
  Map<String, Object?> values,
) {
  final parts = <String, Object?>{
    ...?switch (options[partsOption]) {
      final Map<Object?, Object?> parts => parts.cast<String, Object?>(),
      _ => null,
    },
  };
  final set = {
    ...?switch (parts[part]) {
      final Map<Object?, Object?> set => set.cast<String, Object?>(),
      _ => null,
    },
    ...values,
  }..removeWhere((_, value) => value == null);
  set.isEmpty ? parts.remove(part) : parts[part] = set;
  return {...options, partsOption: parts.isEmpty ? null : parts}
    ..removeWhere((_, value) => value == null);
}
