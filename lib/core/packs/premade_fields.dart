import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/icon_sets.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';

/// Every premade field of every pack, by `<pack>:<name>`.
final premadeFieldsProvider = Provider<Map<String, FieldSpec>>((ref) {
  final packs = ref.watch(packsProvider).value ?? const [];
  return {
    for (final pack in packs)
      for (final MapEntry(:key, :value) in pack.fields.entries)
        '${pack.id}:$key': value,
  };
});
