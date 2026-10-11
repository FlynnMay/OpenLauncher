import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/style/style.dart';

/// The prefab an entity is an instance of unless it names another, and the
/// one an entity that opens a folder is.
const cardPrefabId = 'app-card';
const folderPrefabId = 'folder-card';

// What an instance says of itself is kept in its item's options, under
// these names: which prefab, which of its layouts, and, by part, the
// values it sets differently (`hidden` among them).
const layoutOption = 'layout';
const partsOption = 'parts';

/// Where a part's look is among its options. It is set over property by
/// property, not as a whole: an instance that gives a name its own colour
/// goes on taking the size of its letters from the prefab.
const styleOption = 'style';

/// The options of a part with each of [layers] set over the one before.
Map<String, Object?> layered(List<Map<String, Object?>> layers) {
  final style = <String, Object?>{
    for (final layer in layers) ...styleFromJson(layer[styleOption]),
  };
  return {
    for (final layer in layers) ...layer,
    styleOption: ?style.isEmpty ? null : style,
  };
}

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
/// taken away, which hands that value back to the prefab. So it is with
/// each property of a look among them.
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
  final was = switch (parts[part]) {
    final Map<Object?, Object?> set => set.cast<String, Object?>(),
    _ => const <String, Object?>{},
  };
  final style = withStyle(
    styleFromJson(was[styleOption]),
    switch (values[styleOption]) {
      final Map<Object?, Object?> style => style.cast(),
      _ => const {},
    },
  );
  final set = {...was, ...values, styleOption: style.isEmpty ? null : style}
    ..removeWhere((_, value) => value == null);
  set.isEmpty ? parts.remove(part) : parts[part] = set;
  return {...options, partsOption: parts.isEmpty ? null : parts}
    ..removeWhere((_, value) => value == null);
}
