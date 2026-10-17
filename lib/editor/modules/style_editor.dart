import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// The style properties every selected node draws with.
List<Widget> styleEditor(ModuleEdit edit) => edit.fields(
  stylePropsOf(
    edit.drawn
        .map((node) => node.styleKeys.toSet())
        .reduce((all, own) => all.intersection(own)),
  ),
);
