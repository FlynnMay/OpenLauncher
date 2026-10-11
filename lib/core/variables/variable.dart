import 'package:flutter/foundation.dart';

/// Who may read a variable: only the component it is on, that component
/// and what is inside it, or anything at all.
enum VarAccess {
  private('Only itself'),
  protected('Itself and what is inside it'),
  public('Everything');

  const VarAccess(this.label);

  final String label;
}

/// How a conditional variable tells whether a case is the one.
enum VarTest {
  equals('is'),
  not('is not'),
  above('is more than'),
  below('is less than'),
  contains('contains');

  const VarTest(this.label);

  final String label;
}

/// One case of a conditional variable: what it is ([then]) when what is
/// looked at stands so ([test]) to [value].
@immutable
class VarCase {
  const VarCase(this.test, this.value, this.then);

  final VarTest test;
  final Object? value, then;

  static VarCase? fromJson(Object? json) {
    if (json is! Map) return null;
    for (final test in VarTest.values) {
      if (json.containsKey(test.name)) {
        return VarCase(test, json[test.name], json['then']);
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {test.name: value, 'then': then};

  bool holds(Object? input) {
    num? number(Object? value) => switch (value) {
      final num number => number,
      final String text => num.tryParse(text.trim()),
      _ => null,
    };
    final a = number(input), b = number(value);
    final x = '${input ?? ''}', y = '${value ?? ''}';
    return switch (test) {
      VarTest.equals => a != null && b != null ? a == b : x == y,
      VarTest.not => a != null && b != null ? a != b : x != y,
      VarTest.above => a != null && b != null && a > b,
      VarTest.below => a != null && b != null && a < b,
      VarTest.contains => x.toLowerCase().contains(y.toLowerCase()),
    };
  }
}

/// A named value on a component: text, a number, the id of an entity (it
/// then stands for that entity, and `{{name.label}}` reads it), or a
/// template that reads other values. Having one makes the component an
/// entity itself, read by its id by whoever the variable lets.
///
/// One with a [when] is conditional: [when] is looked at, and it is the
/// `then` of the first of its [cases] that holds, or [otherwise] if none
/// does. Any variable may be set up so.
@immutable
class Variable {
  const Variable(
    this.value, {
    this.access = VarAccess.protected,
    this.when,
    this.cases = const [],
    this.otherwise,
  });

  /// What it is, for one that is not conditional.
  final Object? value;
  final VarAccess access;

  /// What a conditional one looks at: a template.
  final String? when;
  final List<VarCase> cases;
  final Object? otherwise;

  bool get isConditional => when != null;

  Variable copyWith({
    Object? value,
    VarAccess? access,
    String? when,
    List<VarCase>? cases,
    Object? otherwise,
  }) => Variable(
    value ?? this.value,
    access: access ?? this.access,
    when: when ?? this.when,
    cases: cases ?? this.cases,
    otherwise: otherwise ?? this.otherwise,
  );

  /// Never throws. Written short, a variable is its value and nothing
  /// more; written in full it says who may read it, or how it is told.
  factory Variable.fromJson(Object? json) {
    if (json is! Map<Object?, Object?> ||
        !(json.containsKey('value') || json.containsKey('when'))) {
      return Variable(json);
    }
    return Variable(
      json['value'],
      access:
          VarAccess.values.asNameMap()[json['access']] ?? VarAccess.protected,
      when: switch (json['when']) {
        final String looked => looked,
        _ => null,
      },
      cases: [
        if (json['cases'] case final List<Object?> cases)
          for (final entry in cases) ?VarCase.fromJson(entry),
      ],
      otherwise: json['else'],
    );
  }

  Object? toJson() => !isConditional && access == VarAccess.protected
      ? value
      : {
          if (isConditional) ...{
            'when': when,
            'cases': [for (final entry in cases) entry.toJson()],
            'else': otherwise,
          } else
            'value': value,
          if (access != VarAccess.protected) 'access': access.name,
        };

  /// What it is now, where [read] says what a template comes to.
  Object? result(Object? Function(String template) read) {
    Object? told(Object? raw) =>
        raw is String && raw.contains('{{') ? read(raw) : raw;
    if (!isConditional) return told(value);
    final input = read(when!);
    for (final entry in cases) {
      if (VarCase(entry.test, told(entry.value), null).holds(input)) {
        return told(entry.then);
      }
    }
    return told(otherwise);
  }
}

/// The variables of a component, by name.
typedef Variables = Map<String, Variable>;

/// Never throws: what is not a set of variables is none.
Variables variablesFromJson(Object? json) => {
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && key.isNotEmpty) key: Variable.fromJson(value),
};

Map<String, Object?> variablesToJson(Variables variables) => {
  for (final MapEntry(:key, :value) in variables.entries) key: value.toJson(),
};
