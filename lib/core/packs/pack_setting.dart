import 'package:flutter/foundation.dart';

enum PackSettingType { text, number, url, choice, tick, secret }

/// One thing a pack asks the user for, from `settings` in its `pack.json`.
@immutable
class PackSetting {
  const PackSetting(
    this.key,
    this.label,
    this.type, {
    this.choices = const {},
    this.required = false,
  });

  static final _key = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  final String key, label;
  final PackSettingType type;

  /// For a choice: value -> label.
  final Map<String, String> choices;

  /// Whether the pack does nothing until it has a value.
  final bool required;

  bool get secret => type == PackSettingType.secret;

  /// Whether [value] is a usable value of this type.
  bool accepts(Object? value) => switch (type) {
    PackSettingType.text || PackSettingType.secret => value is String,
    PackSettingType.number => value is num,
    PackSettingType.tick => value is bool,
    PackSettingType.choice => value is String && choices.containsKey(value),
    PackSettingType.url =>
      value is String &&
          switch (Uri.tryParse(value.trim())) {
            final uri? =>
              (uri.isScheme('http') || uri.isScheme('https')) &&
                  uri.host.isNotEmpty,
            _ => false,
          },
  };

  static PackSetting? fromJson(String key, Object? json) {
    if (!_key.hasMatch(key) ||
        json is! Map ||
        PackSettingType.values.asNameMap()[json['type']] is! PackSettingType) {
      return null;
    }
    final type = PackSettingType.values.asNameMap()[json['type']]!;
    final choices = {
      if (json['choices'] case final Map<Object?, Object?> choices)
        for (final MapEntry(:key, :value) in choices.entries)
          if (key is String) key: '$value',
    };
    if (type == PackSettingType.choice && choices.isEmpty) return null;
    return PackSetting(
      key,
      json['label'] is String && (json['label'] as String).isNotEmpty
          ? json['label'] as String
          : key,
      type,
      choices: choices,
      required: json['required'] == true,
    );
  }

  /// The settings in a `pack.json` map, by key.
  static List<PackSetting> listFromJson(Object? json) => [
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) ?fromJson(key, value),
  ];

  Map<String, Object?> toJson() => {
    'label': label,
    'type': type.name,
    if (choices.isNotEmpty) 'choices': choices,
    if (required) 'required': true,
  };

  @override
  bool operator ==(Object other) =>
      other is PackSetting &&
      other.key == key &&
      other.label == label &&
      other.type == type &&
      mapEquals(other.choices, choices) &&
      other.required == required;

  @override
  int get hashCode => Object.hash(key, label, type, required);
}
