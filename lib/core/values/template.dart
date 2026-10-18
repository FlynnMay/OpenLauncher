import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/values/expression.dart';

export 'package:openlauncher/core/values/expression.dart'
    show isTruthy, numberOf, valueText;

/// Text with expressions written into it: `{{nowPlaying.title}}` is replaced
/// by the title of what is playing, `{{round(battery.level * 100)}}%` by a
/// sum, `{{wifi.up ? 'Online' : 'Offline'}}` by one of two things. What can
/// stand between the braces is described by [Expression].
///
/// A value there is none of reads as nothing; the template is never wrong,
/// since it is typed by hand and shown as it is typed. [problem] says what
/// did not parse, for an editor to show.
@immutable
class Template {
  const Template._(this._parts);

  factory Template.parse(String source) {
    final parts = <Object>[];
    var end = 0;
    for (final match in _slot.allMatches(source)) {
      if (match.start > end) parts.add(source.substring(end, match.start));
      parts.add(Expression.parse(match[1]!));
      end = match.end;
    }
    if (end < source.length) parts.add(source.substring(end));
    return Template._(parts);
  }

  static final _slot = RegExp(r'\{\{(.*?)\}\}');

  /// Text and [Expression]s, in order.
  final List<Object> _parts;

  /// The first thing in it that did not parse.
  String? get problem => _parts
      .whereType<Expression>()
      .map((expr) => expr.problem)
      .nonNulls
      .firstOrNull;

  /// The roots it reads.
  Set<String> get roots => {
    for (final part in _parts)
      if (part is Expression) ...part.roots,
  };

  /// The value itself when the template is a single expression, keeping its
  /// type; otherwise the rendered text.
  Object? evaluate(Object? Function(String root) lookup) => switch (_parts) {
    [final Expression only] => only.value(lookup),
    _ => render(lookup),
  };

  /// The rendered text.
  String render(Object? Function(String root) lookup) => [
    for (final part in _parts)
      part is Expression ? valueText(part.value(lookup)) : part,
  ].join();

  /// Fills the slots that read only [roots] and leaves the rest as written;
  /// a lone slot keeps its value's type.
  Object? fill(Set<String> roots, Object? Function(String root) lookup) {
    bool known(Expression expr) => roots.containsAll(expr.roots);
    if (_parts case [final Expression only] when known(only)) {
      return only.value(lookup);
    }
    return [
      for (final part in _parts)
        switch (part) {
          final Expression expr when known(expr) => valueText(
            expr.value(lookup),
          ),
          final Expression expr => '{{${expr.source}}}',
          _ => part,
        },
    ].join();
  }
}

/// Every leaf of [value] by its template path, e.g.
/// `lounge.attributes.temperature`.
Map<String, Object?> valuePaths(String root, Object? value) => switch (value) {
  final Map<Object?, Object?> parts => {
    for (final MapEntry(:key, value: part) in parts.entries)
      ...valuePaths('$root.$key', part),
  },
  final List<Object?> several => {
    for (final (index, part) in several.indexed)
      ...valuePaths('$root[$index]', part),
  },
  _ => {root: value},
};
