import 'package:flutter/foundation.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/values/template.dart';

enum PackSettingType { text, number, url, choice, tick, secret, search }

/// One thing a pack asks the user for, from `settings` in its `pack.json`.
@immutable
class PackSetting {
  const PackSetting(
    this.key,
    this.label,
    this.type, {
    this.choices = const {},
    this.required = false,
    this.search,
    this.title = '',
    this.keep = const {},
  });

  static final _key = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  final String key, label;
  final PackSettingType type;

  /// For a choice: value -> label.
  final Map<String, String> choices;

  /// Whether the pack does nothing until it has a value.
  final bool required;

  /// For a search: the source asked with what was typed as `{{query}}`.
  final Source? search;

  /// For a search: a template over a found `row`, how a result is listed. It
  /// is also kept as the chosen value's `name`.
  final String title;

  /// For a search: other keys kept from a found `row`, each a template.
  final Map<String, String> keep;

  bool get secret => type == PackSettingType.secret;

  /// Whether [value] is a usable value of this type.
  bool accepts(Object? value) => switch (type) {
    PackSettingType.text || PackSettingType.secret => value is String,
    PackSettingType.number => value is num,
    PackSettingType.tick => value is bool,
    PackSettingType.choice => value is String && choices.containsKey(value),
    PackSettingType.search =>
      value is Map &&
          '${value['name'] ?? ''}'.isNotEmpty &&
          keep.keys.every(value.containsKey),
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
    final search = Source.fromJson(json['search']);
    final title = json['title'];
    if (type == PackSettingType.search &&
        (search == null || title is! String || title.isEmpty)) {
      return null;
    }
    final keep = {
      if (json['keep'] case final Map<Object?, Object?> keep)
        for (final MapEntry(:key, :value) in keep.entries)
          if (key is String && key != 'name' && value is String) key: value,
    };
    return PackSetting(
      key,
      json['label'] is String && (json['label'] as String).isNotEmpty
          ? json['label'] as String
          : key,
      type,
      choices: choices,
      required: json['required'] == true,
      search: type == PackSettingType.search ? search : null,
      title: type == PackSettingType.search ? title as String : '',
      keep: type == PackSettingType.search ? keep : const {},
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
    if (search != null) ...{
      'search': search!.toJson(),
      'title': title,
      if (keep.isNotEmpty) 'keep': keep,
    },
  };

  /// What a found [row] is listed as, and what choosing it keeps. Null for a
  /// row with no title.
  ({String title, Map<String, Object?> value})? chosenFrom(Object? row) {
    Object? lookup(String root) => root == 'row' ? row : null;
    final listed = Template.parse(title).render(lookup).trim();
    if (listed.isEmpty) return null;
    return (
      title: listed,
      value: {
        'name': listed,
        for (final MapEntry(:key, :value) in keep.entries)
          key: Template.parse(value).evaluate(lookup),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PackSetting &&
      other.key == key &&
      other.label == label &&
      other.type == type &&
      mapEquals(other.choices, choices) &&
      other.required == required &&
      other.search == search &&
      other.title == title &&
      mapEquals(other.keep, keep);

  @override
  int get hashCode => Object.hash(key, label, type, required);
}
