import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// How far a number is between two others, as a bar or a ring.
const meterModule = ModuleType(
  'meter',
  'Meter',
  visual: true,
  size: (2, 1),
  starter: {'value': '{{clock.second}}', 'max': 60},
  styleKeys: ['color'],
  fields: [
    Field('value', 'Value', FieldKind.template),
    // Integers only; scale other values with `| times:`.
    Field(
      'min',
      'Min',
      FieldKind.number,
      defaultValue: 0,
      min: -1000,
      max: 100000,
    ),
    Field(
      'max',
      'Max',
      FieldKind.number,
      defaultValue: 100,
      min: -1000,
      max: 100000,
    ),
    Field(
      'shape',
      'Shape',
      FieldKind.choice,
      defaultValue: 'bar',
      choices: {'bar': 'Bar', 'ring': 'Ring'},
    ),
  ],
);
