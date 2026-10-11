import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component_option.dart';

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

bool _conditional(Map<String, Object?> one) => one['conditional'] == true;

/// What there is to set about the variables of a component: the editor's
/// form for them is made from this, over [variablesToForm].
final variableOptions = ComponentOption(
  'vars',
  'Add a variable',
  OptionKind.list,
  heading: 'name',
  asks: 'Name of the variable',
  blank: const {'name': 'name'},
  fields: (_) => [
    ComponentOption(
      'access',
      'Read by',
      OptionKind.choice,
      usual: VarAccess.protected.name,
      choices: {
        for (final access in VarAccess.values) access.name: access.label,
      },
    ),
    const ComponentOption(
      'conditional',
      'Depends on something',
      OptionKind.toggle,
    ),
    ComponentOption(
      'value',
      'Is',
      OptionKind.template,
      when: (one) => !_conditional(one),
    ),
    const ComponentOption(
      'when',
      'Looks at',
      OptionKind.template,
      when: _conditional,
    ),
    ComponentOption(
      'cases',
      'Add a case',
      OptionKind.list,
      when: _conditional,
      blank: {'test': VarTest.equals.name},
      fields: (_) => [
        ComponentOption(
          'test',
          'When it',
          OptionKind.choice,
          choices: {for (final test in VarTest.values) test.name: test.label},
        ),
        const ComponentOption('value', 'this', OptionKind.value),
        const ComponentOption('then', 'it is', OptionKind.value),
      ],
    ),
    const ComponentOption(
      'else',
      'Otherwise it is',
      OptionKind.value,
      when: _conditional,
    ),
  ],
);

/// [variables] as that form has them: one of each, with its name.
List<Map<String, Object?>> variablesToForm(Variables variables) => [
  for (final MapEntry(key: name, value: variable) in variables.entries)
    {
      'name': name,
      'access': variable.access.name,
      if (variable.isConditional) ...{
        'conditional': true,
        'when': variable.when,
        'cases': [
          for (final entry in variable.cases)
            {'test': entry.test.name, 'value': entry.value, 'then': entry.then},
        ],
        'else': variable.otherwise,
      } else if (variable.value != null)
        'value': '${variable.value}',
    },
];

/// The variables that form says there are. A name keeps only what a
/// template can write, and one with none, or the name of another, is left
/// out.
Variables variablesFromForm(List<Map<String, Object?>> form) {
  final variables = <String, Variable>{};
  for (final one in form) {
    final name = '${one['name'] ?? ''}'.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
    if (name.isEmpty || variables.containsKey(name)) continue;
    final conditional = _conditional(one);
    variables[name] = Variable(
      conditional ? null : typedValue('${one['value'] ?? ''}'),
      access:
          VarAccess.values.asNameMap()[one['access']] ?? VarAccess.protected,
      when: conditional ? '${one['when'] ?? ''}' : null,
      cases: [
        if (one['cases'] case final List<Object?> cases when conditional)
          for (final entry in cases)
            if (entry is Map)
              VarCase(
                VarTest.values.asNameMap()[entry['test']] ?? VarTest.equals,
                entry['value'],
                entry['then'],
              ),
      ],
      otherwise: conditional ? one['else'] : null,
    );
  }
  return variables;
}

/// Never throws: what is not a set of variables is none.
Variables variablesFromJson(Object? json) => {
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && key.isNotEmpty) key: Variable.fromJson(value),
};

Map<String, Object?> variablesToJson(Variables variables) => {
  for (final MapEntry(:key, :value) in variables.entries) key: value.toJson(),
};
