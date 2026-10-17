import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// Which ways it scrolls, then the bar's look once it has one.
List<Widget> scrollEditor(ModuleEdit edit) => [
  ...edit.fields([
    for (final field in edit.type.fields)
      if (!scrollbarStyle.contains(field.key)) field,
  ]),
  if (edit.drawn.every((node) => node.scrollbar != null)) ...[
    const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 4),
      child: Text('Scroll bar look'),
    ),
    ...edit.fields(stylePropsOf(scrollbarStyle)),
  ],
];
