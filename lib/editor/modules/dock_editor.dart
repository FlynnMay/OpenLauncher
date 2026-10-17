import 'package:flutter/widgets.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// Where it docks, its sizes, and how it opens. One node at a time.
List<Widget> dockEditor(ModuleEdit edit) => edit.single
    ? dockFields(edit.shown, edit.onChanged)
    : const [Text('Select one to change where it docks.')];
