import 'package:flutter/foundation.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';

/// One thing a pack asks the user for, from `settings` in its `pack.json`: a
/// key and the [FieldSpec] saying what is asked.
@immutable
class PackSetting {
  const PackSetting(this.key, this.spec);

  static final _key = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  final String key;
  final FieldSpec spec;

  String get label => spec.label.isEmpty ? key : spec.label;
  bool get required => spec.required;
  bool get secret => spec.secret;

  bool accepts(Object? value) => spec.accepts(value);

  /// Every field in it that holds a value, by path: `key` itself, or each
  /// field of a group as `key.part`.
  Iterable<FieldLeaf> get leaves => spec.leaves(key);

  static PackSetting? fromJson(
    String key,
    Object? json, {
    FieldLibrary library = const FieldLibrary(),
    String pack = '',
  }) {
    if (!_key.hasMatch(key)) return null;
    final spec = FieldSpec.fromJson(json, library: library, pack: pack);
    return spec == null ? null : PackSetting(key, spec);
  }

  /// The settings in a `pack.json` map, by key. [pack] is the pack that wrote
  /// them, and [library] has the premade fields they may name.
  static List<PackSetting> listFromJson(
    Object? json, {
    FieldLibrary library = const FieldLibrary(),
    String pack = '',
  }) => [
    if (json is Map)
      for (final MapEntry(:key, :value) in FieldSpec.expandNames(json).entries)
        if (key is String) ?fromJson(key, value, library: library, pack: pack),
  ];

  Map<String, Object?> toJson() => spec.toJson();

  @override
  bool operator ==(Object other) =>
      other is PackSetting && other.key == key && other.spec == spec;

  @override
  int get hashCode => Object.hash(key, spec);
}
