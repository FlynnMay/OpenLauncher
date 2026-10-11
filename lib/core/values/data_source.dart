import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';

/// Where a value the user defined comes from.
enum SourceKind {
  /// Asked of a web address now and then; the JSON it answers with is the
  /// value, and a template reaches into it.
  http('Web address (JSON)'),

  /// Typed in once, to be written in many places and changed in one.
  text('Fixed text');

  const SourceKind(this.label);

  final String label;
}

/// A value the user defined, beside those the launcher has of its own. A
/// template reads it by its [id]: `{{lounge.state}}`.
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

  /// The fewest and most seconds between two askings.
  static const minEvery = 10, maxEvery = 24 * 60 * 60;

  /// How many the user may define.
  static const maxCount = 24;

  final String id;

  /// What the user calls it; the [id] is made from this when it is new.
  final String name;
  final SourceKind kind;

  /// The address asked, for [SourceKind.http].
  final String url;

  /// The value itself, for [SourceKind.text].
  final String text;

  /// Seconds between one asking and the next.
  final int every;

  static bool _asked(Map<String, Object?> one) =>
      one['kind'] != SourceKind.text.name;

  /// What there is to set about the user's values: the editor's form for
  /// them is made from this, over each as it is saved.
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
      // By the TV, while something shows it.
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

  /// Reads the sources in a saved config; what cannot be read is left out,
  /// and no two keep the same id or take the name of one of [taken].
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
