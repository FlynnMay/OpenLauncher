import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';

enum SourceKind {
  /// Polled from a URL; the JSON answer is the value.
  http('Web address (JSON)'),

  text('Fixed text');

  const SourceKind(this.label);

  final String label;
}

/// A user-defined value, read as `{{<id>...}}`.
@immutable
class DataSource {
  const DataSource({
    required this.id,
    this.name = '',
    this.kind = SourceKind.http,
    this.url = '',
    this.text = '',
    this.every = 60,
  });

  /// Bounds of the polling interval, in seconds.
  static const minEvery = 10, maxEvery = 24 * 60 * 60;

  static const maxCount = 24;

  final String id;

  /// Display name; a new [id] is derived from it.
  final String name;
  final SourceKind kind;

  final String url;

  final String text;

  /// Polling interval in seconds.
  final int every;

  static bool _asked(Map<String, Object?> one) =>
      one['kind'] != SourceKind.text.name;

  /// The editor's form is generated from this.
  static final options = ComponentOption(
    'sources',
    'Add a value',
    OptionKind.list,
    heading: 'name',
    asks: 'Name of the value',
    blank: const {'name': 'Value'},
    max: maxCount,
    fields: (_) => [
      const ComponentOption('name', 'Name', OptionKind.text),
      ComponentOption(
        'kind',
        'Comes from',
        OptionKind.choice,
        usual: SourceKind.http.name,
        choices: {for (final kind in SourceKind.values) kind.name: kind.label},
      ),
      ComponentOption(
        'text',
        'Text',
        OptionKind.text,
        when: (one) => !_asked(one),
      ),
      const ComponentOption(
        'url',
        'Web address',
        OptionKind.text,
        when: _asked,
      ),
      // Polled by the TV while something shows it.
      const ComponentOption(
        'every',
        'Seconds between asking',
        OptionKind.number,
        usual: 60,
        min: minEvery,
        max: 3600,
        step: 10,
        when: _asked,
      ),
    ],
  );

  Uri? get address => switch (Uri.tryParse(url.trim())) {
    final uri? when uri.isScheme('http') || uri.isScheme('https') => uri,
    _ => null,
  };

  /// Skips unreadable entries, duplicate ids and ids in [taken].
  static List<DataSource> listFromJson(
    Object? json, {
    Set<String> taken = const {},
  }) {
    final used = {...taken};
    return [
      if (json is List)
        for (final source in json.take(maxCount))
          if (source case {'id': final String id}
              when used.add(id) && id == slugOf(id, ''))
            DataSource(
              id: id,
              name: switch (source['name']) {
                final String name => name,
                _ => '',
              },
              kind:
                  SourceKind.values.asNameMap()[source['kind']] ??
                  SourceKind.http,
              url: switch (source['url']) {
                final String url => url,
                _ => '',
              },
              text: switch (source['text']) {
                final String text => text,
                _ => '',
              },
              every: switch (source['every']) {
                final num every => every.toInt().clamp(minEvery, maxEvery),
                _ => 60,
              },
            ),
    ];
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (kind == SourceKind.http) ...{'url': url, 'every': every},
    if (kind == SourceKind.text) 'text': text,
  };

  @override
  bool operator ==(Object other) =>
      other is DataSource &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.url == url &&
      other.text == text &&
      other.every == every;

  @override
  int get hashCode => Object.hash(id, name, kind, url, text, every);
}
