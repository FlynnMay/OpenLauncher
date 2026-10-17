import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// Who can read a variable.
enum VarAccess {
  private('Private'),
  protected('Protected'),
  public('Public');

  const VarAccess(this.label);

  final String label;
}

/// The comparison a conditional case makes.
enum VarTest {
  equals('is'),
  not('is not'),
  above('is more than'),
  below('is less than'),
  contains('contains');

  const VarTest(this.label);

  final String label;
}

/// One case: the result is [then] when the input passes [test] against
/// [value].
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

/// The type of a variable's value.
enum VarType {
  any('Any'),
  text('Text'),
  number('Number'),
  bool('Boolean'),
  colour('Colour'),

  /// An entity or component id. The variable stands for it, so
  /// `{{name.label}}` works; this is how an entity is passed to children.
  entity('Entity');

  const VarType(this.label);

  final String label;
}

/// A named value on a component.
///
/// With a [when] it is conditional: [when] is evaluated and the result is the
/// `then` of the first matching case, else [otherwise].
@immutable
class Variable {
  const Variable(
    this.value, {
    this.type = VarType.any,
    this.access = VarAccess.protected,
    this.exposed = true,
    this.when,
    this.cases = const [],
    this.otherwise,
  });

  /// The value, when not conditional.
  final Object? value;
  final VarType type;
  final VarAccess access;

  /// On a prefab's root: whether an instance shows it as a field.
  final bool exposed;

  /// This variable with the type and access of [under], its prefab's
  /// declaration, when it sets neither.
  Variable over(Variable? under) =>
      under == null || type != VarType.any || access != VarAccess.protected
      ? this
      : Variable(
          value,
          type: under.type,
          access: under.access,
          exposed: under.exposed,
          when: when,
          cases: cases,
          otherwise: otherwise,
        );

  /// The template a conditional evaluates.
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
      exposed: json['exposed'] != false,
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
      !isConditional &&
          access == VarAccess.protected &&
          type == VarType.any &&
          exposed
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
          if (!exposed) 'exposed': false,
        };

  /// Its current value; [read] evaluates a template.
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

typedef Variables = Map<String, Variable>;

bool _conditional(Map<String, Object?> one) => one['conditional'] == true;

/// Types with a control of their own; `expression` in a row swaps it for a
/// template.
const _fixed = {VarType.number, VarType.bool, VarType.colour, VarType.entity};

/// Whether the form row [one] is of a type with a control of its own.
bool hasTypedValue(Map<String, Object?> one) =>
    !_conditional(one) && _fixed.any((type) => type.name == one['type']);

bool Function(Map<String, Object?> one) _valueOf(VarType type) =>
    (one) =>
        hasTypedValue(one) &&
        one['type'] == type.name &&
        one['expression'] != true;

/// The editor's form is generated from this, over [variablesToForm]. An
/// entity-typed value is one of [entities], id to label. [exposable] adds
/// the tick a prefab's own variables have.
Field variableOptions({
  Map<String, String> entities = const {},
  bool exposable = false,
}) => Field(
  'vars',
  'Add variable',
  FieldKind.list,
  heading: 'name',
  asks: 'Variable name',
  blank: const {'name': 'name'},
  fields: (one) => [
    Field(
      'type',
      'Type',
      FieldKind.choice,
      defaultValue: VarType.any.name,
      choices: {for (final type in VarType.values) type.name: type.label},
    ),
    Field(
      'access',
      'Access',
      FieldKind.choice,
      defaultValue: VarAccess.protected.name,
      choices: {
        for (final access in VarAccess.values) access.name: access.label,
      },
    ),
    if (exposable)
      const Field('exposed', 'Exposed', FieldKind.toggle, defaultValue: true),
    const Field('conditional', 'Conditional', FieldKind.toggle),
    const Field(
      'expression',
      'Expression',
      FieldKind.toggle,
      when: hasTypedValue,
    ),
    Field(
      'value',
      'Value',
      FieldKind.template,
      when: (one) =>
          !_conditional(one) &&
          (!hasTypedValue(one) || one['expression'] == true),
    ),
    Field(
      'value',
      'Value',
      FieldKind.number,
      min: -1000000,
      max: 1000000,
      decimal: true,
      when: _valueOf(VarType.number),
    ),
    Field('value', 'Value', FieldKind.toggle, when: _valueOf(VarType.bool)),
    Field('value', 'Value', FieldKind.colour, when: _valueOf(VarType.colour)),
    Field(
      'value',
      'Value',
      FieldKind.choice,
      unset: 'None',
      choices: {
        // Keeps a saved one that is not there now.
        if (one['value'] case final String saved when saved.isNotEmpty)
          saved: saved,
        ...entities,
      },
      when: _valueOf(VarType.entity),
    ),
    const Field('when', 'Based on', FieldKind.template, when: _conditional),
    Field(
      'cases',
      'Add case',
      FieldKind.list,
      when: _conditional,
      blank: {'test': VarTest.equals.name},
      fields: (_) => [
        Field(
          'test',
          'If it',
          FieldKind.choice,
          choices: {for (final test in VarTest.values) test.name: test.label},
        ),
        const Field('value', 'Value', FieldKind.value),
        const Field('then', 'Then', FieldKind.value),
      ],
    ),
    const Field('else', 'Else', FieldKind.value, when: _conditional),
  ],
);

/// [variables] as rows for that form.
List<Map<String, Object?>> variablesToForm(Variables variables) => [
  for (final MapEntry(key: name, value: variable) in variables.entries)
    {
      'name': name,
      'type': variable.type.name,
      'access': variable.access.name,
      if (!variable.exposed) 'exposed': false,
      if (variable.isConditional) ...{
        'conditional': true,
        'when': variable.when,
        'cases': [
          for (final entry in variable.cases)
            {'test': entry.test.name, 'value': entry.value, 'then': entry.then},
        ],
        'else': variable.otherwise,
      } else if (variable.value case final value?) ...{
        if (value is String && value.contains('{{')) 'expression': true,
        // A number or a yes/no goes to its own control as it is.
        'value': switch (variable.type) {
          VarType.number when value is num => value,
          VarType.bool when value is bool => value,
          _ => '$value',
        },
      },
    },
];

/// Variables from form rows. Names are reduced to `[A-Za-z0-9_]`; empty and
/// duplicate names are skipped.
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
      exposed: one['exposed'] != false,
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

/// Never throws.
Variables variablesFromJson(Object? json) => {
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && key.isNotEmpty) key: Variable.fromJson(value),
};

Map<String, Object?> variablesToJson(Variables variables) => {
  for (final MapEntry(:key, :value) in variables.entries) key: value.toJson(),
};
