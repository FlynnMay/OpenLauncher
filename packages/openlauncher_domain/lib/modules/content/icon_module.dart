import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// A pack's icon, by name.
const iconModule = ModuleType(
  'icon',
  'Icon',
  visual: true,
  styleKeys: ['color'],
  fields: [
    Field('icon', 'Icon', FieldKind.icon),
    Field(
      'size',
      'Size',
      FieldKind.number,
      min: 8,
      max: 200,
      step: 2,
      unset: 'Auto',
    ),
  ],
);
