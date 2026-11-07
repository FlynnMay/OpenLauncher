import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/style/style.dart';

bool _scrolling(Map<String, Object?> values) => values['overflow'] == 'scroll';

/// Text made of values.
const textModule = ModuleType(
  'text',
  'Text',
  visual: true,
  size: (2, 1),
  starter: {'text': '{{clock.time}}'},
  styleKeys: textStyle,
  fields: [
    Field('text', 'Text', FieldKind.template),
    // Only applies with a fixed font size.
    Field(
      'overflow',
      'Overflow',
      FieldKind.choice,
      defaultValue: 'fade',
      choices: {
        'fade': 'Fade',
        'ellipsis': 'Ellipsis',
        'clip': 'Clip',
        'wrap': 'Wrap',
        'scroll': 'Scroll',
      },
    ),
    Field(
      'speed',
      'Scroll speed',
      FieldKind.number,
      defaultValue: 40,
      min: 10,
      max: 300,
      step: 10,
      when: _scrolling,
    ),
  ],
);
