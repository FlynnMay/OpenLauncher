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

/// What sort of value a variable holds. One of no sort holds anything.
enum VarType {
  any('Anything'),
  text('Text'),
  number('A number'),
  bool('Yes or no'),
  colour('A colour'),

  /// The id of an entity, or of a component that is one: the variable
  /// then stands for it, and `{{name.label}}` reads it. This is how
  /// something is handed to what is inside a component.
  entity('An entity');

  const VarType(this.label);

  final String label;
}

/// A named value on a component, of some [type]: text, a number, a
/// colour, an entity, or a template that reads other values. Having one makes the component an
/// entity itself, read by its id by whoever the variable lets.
///
/// One with a [when] is conditional: [when] is looked at, and it is the
/// `then` of the first of its [cases] that holds, or [otherwise] if none
/// does. Any variable may be set up so.
@immutable
class Variable {
  const Variable(
    this.value, {
    this.type = VarType.any,
    this.access = VarAccess.protected,
    this.when,
    this.cases = const [],
    this.otherwise,
  });

  /// What it is, for one that is not conditional.
  final Object? value;
  final VarType type;
  final VarAccess access;

  /// This variable as one set over [under], the one of its name in the
  /// prefab it is an instance of: what sort it is and who may read it are
  /// the prefab's to say, where this says neither.
  Variable over(Variable? under) =>
      under == null || type != VarType.any || access != VarAccess.protected
      ? this
      : Variable(
          value,
          type: under.type,
          access: under.access,
          when: when,
          cases: cases,
          otherwise: otherwise,
        );

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
      type: VarType.values.asNameMap()[json['type']] ?? VarType.any,
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

  Object? toJson() =>
      !isConditional && access == VarAccess.protected && type == VarType.any
      ? value
      : {
          if (isConditional) ...{
            'when': when,
            'cases': [for (final entry in cases) entry.toJson()],
            'else': otherwise,
          } else
            'value': value,
          if (type != VarType.any) 'type': type.name,
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
bool _colour(Map<String, Object?> one) => one['type'] == VarType.colour.name;

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
      'type',
      'Holds',
      OptionKind.choice,
      usual: VarType.any.name,
      choices: {for (final type in VarType.values) type.name: type.label},
    ),
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
      when: (one) => !_conditional(one) && !_colour(one),
    ),
    ComponentOption(
      'value',
      'Is',
      OptionKind.colour,
      when: (one) => !_conditional(one) && _colour(one),
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
      'type': variable.type.name,
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
      type: VarType.values.asNameMap()[one['type']] ?? VarType.any,
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
