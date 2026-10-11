import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/values/date_format.dart';

/// Text with values written into it: `{{nowPlaying.title}}` is replaced by
/// the title of what is playing. A value is named by a path from one of the
/// roots there are (`time`, `weather`, a source the user made...), through
/// `.name` and `[0]`; after it, `| name:argument` changes how it reads:
///
/// - `default:nothing` — what to say when there is no value
/// - `round` / `round:1` — a number to so many decimal places
/// - `times:1.8`, `plus:32` — sums
/// - `upper`, `lower`
/// - `format:h:mm a` — a time, written as `formatDateTime` does
///
/// A value there is none of reads as nothing; the template is never wrong,
/// since it is typed by hand and shown as it is typed.
@immutable
class Template {
  const Template._(this._parts);

  factory Template.parse(String source) {
    final parts = <Object>[];
    var end = 0;
    for (final match in _slot.allMatches(source)) {
      if (match.start > end) parts.add(source.substring(end, match.start));
      parts.add(_Slot.parse(match[1]!));
      end = match.end;
    }
    if (end < source.length) parts.add(source.substring(end));
    return Template._(parts);
  }

  static final _slot = RegExp(r'\{\{(.*?)\}\}');

  /// Text and [_Slot]s, in order.
  final List<Object> _parts;

  /// The roots whose values it reads.
  Set<String> get roots => {
    for (final part in _parts)
      if (part is _Slot && part.path.isNotEmpty) '${part.path.first}',
  };

  /// How it reads when each root is what [lookup] says it is.
  String render(Object? Function(String root) lookup) => [
    for (final part in _parts)
      part is _Slot ? valueText(part.value(lookup)) : part,
  ].join();
}

/// How a value reads: a whole number without its `.0`, a thing of several
/// parts by its `text` part.
String valueText(Object? value) => switch (value) {
  null => '',
  final double number when number == number.roundToDouble() =>
    '${number.round()}',
  final Map<Object?, Object?> parts => valueText(parts['text']),
  final List<Object?> several => several.map(valueText).join(', '),
  _ => '$value',
};

/// Every single value in [value] with the path that names it, as it is
/// written in a template: `lounge.attributes.temperature`.
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

class _Slot {
  const _Slot(this.path, this.pipes);

  factory _Slot.parse(String source) {
    final [path, ...pipes] = source.split('|');
    return _Slot(
      [
        for (final step in path.trim().split(RegExp(r'[.\[\]]+')))
          if (step.isNotEmpty) int.tryParse(step) ?? step,
      ],
      [
        for (final pipe in pipes)
          switch (pipe.indexOf(':')) {
            -1 => (name: pipe.trim(), argument: ''),
            // Only the first: a time's pattern has colons of its own.
            final colon => (
              name: pipe.substring(0, colon).trim(),
              argument: _unquoted(pipe.substring(colon + 1).trim()),
            ),
          },
      ],
    );
  }

  /// Names and places in a list, from the root down.
  final List<Object> path;
  final List<({String name, String argument})> pipes;

  static String _unquoted(String text) =>
      text.length > 1 && text.startsWith('"') && text.endsWith('"')
      ? text.substring(1, text.length - 1)
      : text;

  static num? _number(Object? value) => switch (value) {
    final num number => number,
    final String text => num.tryParse(text.trim()),
    final Map<Object?, Object?> parts => _number(parts['text']),
    _ => null,
  };

  static DateTime? _time(Object? value) => switch (value) {
    {'epoch': final num epoch} => DateTime.fromMillisecondsSinceEpoch(
      epoch.toInt(),
    ),
    // Too small to be thousandths of a second: whole seconds, as most
    // APIs count them.
    final num epoch => DateTime.fromMillisecondsSinceEpoch(
      (epoch.abs() < 1e11 ? epoch * 1000 : epoch).toInt(),
    ),
    final String text => DateTime.tryParse(text.trim())?.toLocal(),
    _ => null,
  };

  Object? value(Object? Function(String root) lookup) {
    if (path.isEmpty) return null;
    var value = lookup('${path.first}');
    for (final step in path.skip(1)) {
      value = switch (value) {
        final Map<Object?, Object?> parts => parts['$step'],
        final List<Object?> several
            when step is int && step >= 0 && step < several.length =>
          several[step],
        _ => null,
      };
    }
    for (final (:name, :argument) in pipes) {
      final number = _number(value);
      value = switch (name) {
        'default' => valueText(value).isEmpty ? argument : value,
        'upper' => valueText(value).toUpperCase(),
        'lower' => valueText(value).toLowerCase(),
        'round' when number != null => switch (int.tryParse(argument) ?? 0) {
          <= 0 => number.round(),
          final places => number.toStringAsFixed(places.clamp(1, 6)),
        },
        'times' when number != null => number * (num.tryParse(argument) ?? 1),
        'plus' when number != null => number + (num.tryParse(argument) ?? 0),
        'format' => switch (_time(value)) {
          null => value,
          final time => formatDateTime(time, argument),
        },
        // Unknown, or not for this kind of value: as it was.
        _ => value,
      };
    }
    return value;
  }
}
