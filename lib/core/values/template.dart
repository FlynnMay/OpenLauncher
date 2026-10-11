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
/// Two values can be compared, with spaces around `==`, `!=`, `>`, `<`,
/// `>=` or `<=`, and one of two things said by which way that falls:
/// `{{media.playing == true ? 'pause' : 'play'}}`. What stands either side
/// is a value's path, a number, `true`, `false`, or text between quotes.
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
      parts.add(_Expr.parse(match[1]!));
      end = match.end;
    }
    if (end < source.length) parts.add(source.substring(end));
    return Template._(parts);
  }

  static final _slot = RegExp(r'\{\{(.*?)\}\}');

  /// Text and [_Expr]s, in order.
  final List<Object> _parts;

  /// The roots it reads.
  Set<String> get roots => {
    for (final part in _parts)
      if (part is _Expr) ...part.roots,
  };

  /// The value itself when the template is a single expression, keeping its
  /// type; otherwise the rendered text.
  Object? evaluate(Object? Function(String root) lookup) => switch (_parts) {
    [final _Expr only] => only.value(lookup),
    _ => render(lookup),
  };

  /// The rendered text.
  String render(Object? Function(String root) lookup) => [
    for (final part in _parts)
      part is _Expr ? valueText(part.value(lookup)) : part,
  ].join();
}

/// A value as text: whole numbers without `.0`, a map by its `text`.
String valueText(Object? value) => switch (value) {
  null => '',
  final double number when number == number.roundToDouble() =>
    '${number.round()}',
  final Map<Object?, Object?> parts => valueText(parts['text']),
  final List<Object?> several => several.map(valueText).join(', '),
  _ => '$value',
};

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

/// One `{{...}}`: a value, a comparison, or a ternary.
class _Expr {
  const _Expr(this.left, [this.op, this.right, this.yes, this.no]);

  factory _Expr.parse(String source) {
    var condition = source;
    _Slot? yes, no;
    // Needs spaces, so `default:?` stays a pipe argument.
    final asks = _outside(source, ' ? ');
    if (asks != -1) {
      final rest = source.substring(asks + 3);
      final or = _outside(rest, ' : ');
      if (or != -1) {
        condition = source.substring(0, asks);
        yes = _Slot.parse(rest.substring(0, or));
        no = _Slot.parse(rest.substring(or + 3));
      }
    }
    for (final op in const [' == ', ' != ', ' >= ', ' <= ', ' > ', ' < ']) {
      final at = _outside(condition, op);
      if (at == -1) continue;
      return _Expr(
        _Slot.parse(condition.substring(0, at)),
        op.trim(),
        _Slot.parse(condition.substring(at + op.length)),
        yes,
        no,
      );
    }
    return _Expr(_Slot.parse(condition), null, null, yes, no);
  }

  final _Slot left;
  final String? op;
  final _Slot? right, yes, no;

  /// The first [mark] in [text] outside quotes, or -1.
  static int _outside(String text, String mark) {
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (text.startsWith(mark, i)) {
        return i;
      }
    }
    return -1;
  }

  Iterable<String> get roots => [
    for (final slot in [left, ?right, ?yes, ?no])
      if (slot.literal == null && slot.path.isNotEmpty) '${slot.path.first}',
  ];

  static bool _truthy(Object? value) => switch (value) {
    null || false || 0 || '' || 'false' => false,
    final Map<Object?, Object?> parts => _truthy(parts['text']),
    _ => true,
  };

  bool _holds(Object? a, Object? b) {
    final x = _Slot._number(a), y = _Slot._number(b);
    final order = x != null && y != null
        ? x.compareTo(y)
        : valueText(a).compareTo(valueText(b));
    return switch (op) {
      '==' => order == 0,
      '!=' => order != 0,
      '>' => order > 0,
      '<' => order < 0,
      '>=' => order >= 0,
      _ => order <= 0,
    };
  }

  Object? value(Object? Function(String root) lookup) {
    final first = left.value(lookup);
    if (op == null && yes == null) return first;
    final holds = op == null
        ? _truthy(first)
        : _holds(first, right!.value(lookup));
    if (yes == null) return holds;
    return (holds ? yes : no)!.value(lookup);
  }
}

class _Slot {
  const _Slot(this.path, this.pipes, [this.literal]);

  /// A literal: quoted text, a number, `true` or `false`.
  static Object? _said(String source) {
    final text = source.trim();
    if (text.length > 1 &&
        (text.startsWith("'") && text.endsWith("'") ||
            text.startsWith('"') && text.endsWith('"'))) {
      return text.substring(1, text.length - 1);
    }
    return switch (text) {
      'true' => true,
      'false' => false,
      _ => num.tryParse(text),
    };
  }

  factory _Slot.parse(String source) {
    if (_said(source) case final said?) return _Slot(const [], const [], said);
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
            // Only the first colon; a time pattern has its own.
            final colon => (
              name: pipe.substring(0, colon).trim(),
              argument: _unquoted(pipe.substring(colon + 1).trim()),
            ),
          },
      ],
    );
  }

  /// Names and indexes, from the root down.
  final List<Object> path;
  final List<({String name, String argument})> pipes;

  /// The value, for a literal.
  final Object? literal;

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
    // Too small for milliseconds, so seconds.
    final num epoch => DateTime.fromMillisecondsSinceEpoch(
      (epoch.abs() < 1e11 ? epoch * 1000 : epoch).toInt(),
    ),
    final String text => DateTime.tryParse(text.trim())?.toLocal(),
    _ => null,
  };

  Object? value(Object? Function(String root) lookup) {
    if (literal != null) return literal;
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
        // Unknown pipe, or wrong type: unchanged.
        _ => value,
      };
    }
    return value;
  }
}
