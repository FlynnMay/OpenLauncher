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

  static PackSetting? fromJson(String key, Object? json) {
    if (!_key.hasMatch(key)) return null;
    final spec = FieldSpec.fromJson(json);
    return spec == null ? null : PackSetting(key, spec);
  }

  /// The settings in a `pack.json` map, by key.
  static List<PackSetting> listFromJson(Object? json) => [
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) ?fromJson(key, value),
  ];

  Map<String, Object?> toJson() => spec.toJson();

  @override
  bool operator ==(Object other) =>
      other is PackSetting && other.key == key && other.spec == spec;

  @override
  int get hashCode => Object.hash(key, spec);
}
