import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// A picture from a web address, a file or a value.
const pictureModule = ModuleType(
  'picture',
  'Picture',
  visual: true,
  size: (2, 2),
  styleKeys: ['radius'],
  fields: [
    Field('source', 'Source (URL or value)', FieldKind.template),
    Field('alt', 'Alt text', FieldKind.template),
    Field('badge', 'Badge', FieldKind.template),
    Field(
      'fit',
      'Fit',
      FieldKind.choice,
      defaultValue: 'cover',
      choices: {'cover': 'Cover', 'contain': 'Contain'},
    ),
  ],
);
