import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/values/date_format.dart';

/// What stands between `{{` and `}}`: a value, or an expression over values.
///
/// - A value is a path from a root, through `.name` and `[0]`
///   (`lounge.attributes.readings[1]`), a number, `'text'` or `"text"`,
///   `true`, `false` or `null`.
/// - Math: `+ - * / %` and brackets. `-` needs a space either side, since a
///   name may hold one (`a-b`). Text can be joined with `+`.
/// - Comparing: `== != < > <= >=`; logic: `&& || !`. `&&` and `||` give the
///   operand that decided them, so `a || 'none'` is a fallback.
/// - `a ?? b` is `b` where `a` is nothing or empty.
/// - `condition ? yes : no`, with a space either side of `?` and `:`; or
///   `if(condition, yes, no)`.
/// - Functions: `round(x)` / `round(x, places)`, `floor`, `ceil`, `abs`,
///   `min`, `max`, `clamp(x, low, high)`, `upper`, `lower`, `if`.
/// - After all that, `| name:argument` changes how the result reads, as
///   [pipe] lists.
///
/// One that does not parse is [problem] and reads as nothing.
@immutable
class Expression {
  const Expression._(this.source, this._tree, this._pipes, this.problem);

  factory Expression.parse(String source) {
    final cut = _pipeAt(source);
    final head = cut == -1 ? source : source.substring(0, cut);
    final pipes = cut == -1
        ? const <_Pipe>[]
        : [
            for (final step in source.substring(cut + 1).split('|'))
              switch (step.indexOf(':')) {
                -1 => (name: step.trim(), argument: ''),
                // Only the first colon; a time pattern has its own.
                final colon => (
                  name: step.substring(0, colon).trim(),
                  argument: _unquoted(step.substring(colon + 1).trim()),
                ),
              },
          ];
    try {
      return Expression._(source, _Parser(head).parse(), pipes, null);
    } on FormatException catch (error) {
      return Expression._(source, null, pipes, error.message);
    }
  }

  /// As written between the braces.
  final String source;

  final _Node? _tree;
  final List<_Pipe> _pipes;

  /// Why it did not parse, if it did not.
  final String? problem;

  /// The roots it reads.
  Set<String> get roots => {...?_tree?.roots};

  Object? value(Object? Function(String root) lookup) {
    var value = _tree?.value(lookup);
    for (final step in _pipes) {
      value = pipe(value, step.name, step.argument);
    }
    return value;
  }

  /// The first `|` outside quotes that is not half of `||`, or -1.
  static int _pipeAt(String text) {
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '|') {
        if (text.startsWith('||', i)) {
          i++;
        } else {
          return i;
        }
      }
    }
    return -1;
  }

  static String _unquoted(String text) =>
      text.length > 1 && text.startsWith('"') && text.endsWith('"')
      ? text.substring(1, text.length - 1)
      : text;
}

typedef _Pipe = ({String name, String argument});

/// Whether a condition holds: not null, false, 0 or empty.
bool isTruthy(Object? value) => switch (value) {
  null || false || 0 || '' || 'false' => false,
  final Map<Object?, Object?> parts => isTruthy(parts['text']),
  _ => true,
};

/// A value as text: whole numbers without `.0`, a map by its `text`.
String valueText(Object? value) => switch (value) {
  null => '',
  final double number when number == number.roundToDouble() =>
    '${number.round()}',
  final Map<Object?, Object?> parts => valueText(parts['text']),
  final List<Object?> several => several.map(valueText).join(', '),
  _ => '$value',
};

/// A value as a number, if it reads as one.
num? numberOf(Object? value) => switch (value) {
  final num number => number,
  final String text => num.tryParse(text.trim()),
  final Map<Object?, Object?> parts => numberOf(parts['text']),
  _ => null,
};

DateTime? _time(Object? value) => switch (value) {
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

/// Nothing when [pattern] finds nothing or is not one.
String? _match(String pattern, String text) {
  try {
    final found = RegExp(pattern).firstMatch(text);
    if (found == null) return null;
    return found.groupCount > 0 ? found[1] : found[0];
  } on FormatException {
    return null;
  }
}

/// [value] changed the way pipe [name] says, with its [argument]:
///
/// - `default:nothing` — what to say when there is no value
/// - `round` / `round:1` — a number to so many decimal places
/// - `times:1.8`, `plus:32` — sums
/// - `upper`, `lower`
/// - `format:h:mm a` — a time, written as `formatDateTime` does
/// - `match:(\d+)$` — the first group a pattern finds, else all it finds
///
/// Unknown, or for the wrong kind of value: unchanged.
Object? pipe(Object? value, String name, String argument) {
  final number = numberOf(value);
  return switch (name) {
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
    'match' => _match(argument, valueText(value)),
    _ => value,
  };
}

// Parsing.

sealed class _Node {
  const _Node();

  Iterable<String> get roots;

  Object? value(Object? Function(String root) lookup);
}

class _Literal extends _Node {
  const _Literal(this.literal);

  final Object? literal;

  @override
  Iterable<String> get roots => const [];

  @override
  Object? value(Object? Function(String root) lookup) => literal;
}

class _Path extends _Node {
  const _Path(this.steps);

  /// Names and indexes, from the root down.
  final List<Object> steps;

  @override
  Iterable<String> get roots => ['${steps.first}'];

  @override
  Object? value(Object? Function(String root) lookup) {
    var value = lookup('${steps.first}');
    for (final step in steps.skip(1)) {
      value = switch (value) {
        final Map<Object?, Object?> parts => parts['$step'],
        final List<Object?> several
            when step is int && step >= 0 && step < several.length =>
          several[step],
        _ => null,
      };
    }
    return value;
  }
}

class _Not extends _Node {
  const _Not(this.operand);

  final _Node operand;

  @override
  Iterable<String> get roots => operand.roots;

  @override
  Object? value(Object? Function(String root) lookup) =>
      !isTruthy(operand.value(lookup));
}

class _Negative extends _Node {
  const _Negative(this.operand);

  final _Node operand;

  @override
  Iterable<String> get roots => operand.roots;

  @override
  Object? value(Object? Function(String root) lookup) {
    final number = numberOf(operand.value(lookup));
    return number == null ? null : -number;
  }
}

class _Binary extends _Node {
  const _Binary(this.op, this.left, this.right);

  final String op;
  final _Node left, right;

  @override
  Iterable<String> get roots => [...left.roots, ...right.roots];

  @override
  Object? value(Object? Function(String root) lookup) {
    final a = left.value(lookup);
    switch (op) {
      case '&&':
        return isTruthy(a) ? right.value(lookup) : a;
      case '||':
        return isTruthy(a) ? a : right.value(lookup);
      case '??':
        return valueText(a).isEmpty ? right.value(lookup) : a;
    }
    final b = right.value(lookup);
    switch (op) {
      case '==' || '!=' || '<' || '>' || '<=' || '>=':
        final x = numberOf(a), y = numberOf(b);
        final order = x != null && y != null
            ? x.compareTo(y)
            : valueText(a).compareTo(valueText(b));
        return switch (op) {
          '==' => order == 0,
          '!=' => order != 0,
          '<' => order < 0,
          '>' => order > 0,
          '<=' => order <= 0,
          _ => order >= 0,
        };
    }
    final x = numberOf(a), y = numberOf(b);
    if (op == '+' && (x == null || y == null)) {
      return '${valueText(a)}${valueText(b)}';
    }
    if (x == null || y == null) return null;
    return switch (op) {
      '+' => x + y,
      '-' => x - y,
      '*' => x * y,
      '/' => y == 0 ? null : x / y,
      _ => y == 0 ? null : x % y,
    };
  }
}

class _Ask extends _Node {
  const _Ask(this.condition, this.yes, this.no);

  final _Node condition, yes, no;

  @override
  Iterable<String> get roots => [...condition.roots, ...yes.roots, ...no.roots];

  @override
  Object? value(Object? Function(String root) lookup) =>
      (isTruthy(condition.value(lookup)) ? yes : no).value(lookup);
}

class _Call extends _Node {
  const _Call(this.name, this.args);

  final String name;
  final List<_Node> args;

  @override
  Iterable<String> get roots => [for (final arg in args) ...arg.roots];

  @override
  Object? value(Object? Function(String root) lookup) {
    // Only the branch taken is read.
    if (name == 'if') {
      return (isTruthy(args[0].value(lookup)) ? args[1] : args[2]).value(
        lookup,
      );
    }
    final values = [for (final arg in args) arg.value(lookup)];
    final numbers = [for (final value in values) numberOf(value)];
    num? first() => numbers.isEmpty ? null : numbers.first;
    if (name == 'upper') return valueText(values.first).toUpperCase();
    if (name == 'lower') return valueText(values.first).toLowerCase();
    if (numbers.contains(null)) return null;
    return switch (name) {
      'round' when numbers.length == 2 =>
        numbers[1]! <= 0
            ? numbers[0]!.round()
            : numbers[0]!.toStringAsFixed(numbers[1]!.round().clamp(1, 6)),
      'round' => first()!.round(),
      'floor' => first()!.floor(),
      'ceil' => first()!.ceil(),
      'abs' => first()!.abs(),
      'min' => numbers.reduce((a, b) => a! < b! ? a : b),
      'max' => numbers.reduce((a, b) => a! > b! ? a : b),
      _ =>
        numbers[1]! > numbers[2]!
            ? numbers[1]
            : numbers[0]!.clamp(numbers[1]!, numbers[2]!),
    };
  }
}

/// How many arguments a function takes, from to.
const _arity = {
  'round': (1, 2),
  'floor': (1, 1),
  'ceil': (1, 1),
  'abs': (1, 1),
  'min': (1, 99),
  'max': (1, 99),
  'clamp': (3, 3),
  'upper': (1, 1),
  'lower': (1, 1),
  'if': (3, 3),
};

typedef _Token = ({String kind, String text});

class _Parser {
  _Parser(String source) : _tokens = _tokenize(source);

  final List<_Token> _tokens;
  var _at = 0;

  static const _symbols = [
    '??', '||', '&&', '==', '!=', '>=', '<=', //
    '>', '<', '+', '*', '/', '%', '!', '(', ')', ',', '?', ':', '-',
  ];

  static bool _wordStart(String char) => RegExp(r'[A-Za-z_]').hasMatch(char);

  // A name may hold `.`, `:`, `-`, `[` and `]` after its first letter.
  static bool _wordPart(String char) =>
      RegExp(r'[A-Za-z0-9_.:\[\]\-]').hasMatch(char);

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char.trim().isEmpty) {
        i++;
      } else if (char == "'" || char == '"') {
        final end = source.indexOf(char, i + 1);
        if (end == -1) throw const FormatException('Unclosed quote');
        tokens.add((kind: 'text', text: source.substring(i + 1, end)));
        i = end + 1;
      } else if (RegExp(r'[0-9]').hasMatch(char)) {
        final number = RegExp(r'\d+(\.\d+)?').matchAsPrefix(source, i)![0]!;
        tokens.add((kind: 'number', text: number));
        i += number.length;
      } else if (_wordStart(char)) {
        var end = i + 1;
        while (end < source.length && _wordPart(source[end])) {
          end++;
        }
        // A trailing `:` or `.` belongs to what follows.
        while (end > i + 1 && ':.-'.contains(source[end - 1])) {
          end--;
        }
        tokens.add((kind: 'word', text: source.substring(i, end)));
        i = end;
      } else {
        final symbol = _symbols.where((s) => source.startsWith(s, i));
        if (symbol.isEmpty) throw FormatException("Unexpected '$char'");
        tokens.add((kind: 'symbol', text: symbol.first));
        i += symbol.first.length;
      }
    }
    return tokens;
  }

  _Token? get _next => _at < _tokens.length ? _tokens[_at] : null;

  bool _is(String symbol) =>
      _next != null && _next!.kind == 'symbol' && _next!.text == symbol;

  bool _take(String symbol) {
    if (!_is(symbol)) return false;
    _at++;
    return true;
  }

  void _expect(String symbol) {
    if (!_take(symbol)) throw FormatException("Expected '$symbol'");
  }

  _Node parse() {
    if (_tokens.isEmpty) return const _Literal(null);
    final tree = _ask();
    if (_next != null) throw FormatException("Unexpected '${_next!.text}'");
    return tree;
  }

  _Node _ask() {
    final condition = _binary(0);
    if (!_take('?')) return condition;
    final yes = _ask();
    _expect(':');
    return _Ask(condition, yes, _ask());
  }

  static const _levels = [
    ['??'],
    ['||'],
    ['&&'],
    ['==', '!='],
    ['<', '>', '<=', '>='],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  _Node _binary(int level) {
    if (level == _levels.length) return _unary();
    var left = _binary(level + 1);
    while (_next != null &&
        _next!.kind == 'symbol' &&
        _levels[level].contains(_next!.text)) {
      final op = _tokens[_at++].text;
      left = _Binary(op, left, _binary(level + 1));
    }
    return left;
  }

  _Node _unary() {
    if (_take('!')) return _Not(_unary());
    if (_take('-')) return _Negative(_unary());
    return _primary();
  }

  _Node _primary() {
    final token = _next;
    if (token == null) throw const FormatException('Expected a value');
    _at++;
    switch (token.kind) {
      case 'number':
        return _Literal(num.parse(token.text));
      case 'text':
        return _Literal(token.text);
      case 'word':
        if (_is('(')) return _call(token.text);
        return switch (token.text) {
          'true' => const _Literal(true),
          'false' => const _Literal(false),
          'null' => const _Literal(null),
          final name => _Path([
            for (final step in name.split(RegExp(r'[.\[\]]+')))
              if (step.isNotEmpty) int.tryParse(step) ?? step,
          ]),
        };
    }
    if (token.text == '(') {
      final inside = _ask();
      _expect(')');
      return inside;
    }
    throw FormatException("Unexpected '${token.text}'");
  }

  _Node _call(String name) {
    final arity = _arity[name];
    if (arity == null) throw FormatException("Unknown function '$name'");
    _expect('(');
    final args = <_Node>[];
    if (!_is(')')) {
      do {
        args.add(_ask());
      } while (_take(','));
    }
    _expect(')');
    final (least, most) = arity;
    if (args.length < least || args.length > most) {
      throw FormatException("'$name' takes $least to $most values");
    }
    return _Call(name, args);
  }
}
