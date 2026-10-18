import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/modules/app_widget_editor.dart';
import 'package:openlauncher/editor/modules/dock_editor.dart';
import 'package:openlauncher/editor/modules/layout_editor.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/modules/prefab_rules_editor.dart';
import 'package:openlauncher/editor/modules/scroll_editor.dart';
import 'package:openlauncher/editor/modules/sizing_editor.dart';
import 'package:openlauncher/editor/modules/style_editor.dart';
import 'package:openlauncher/editor/modules/triggers_editor.dart';
import 'package:openlauncher/editor/modules/variables_editor.dart';
import 'package:openlauncher/editor/modules/wallpaper_editor.dart';

/// Modules whose section needs more than fields generated from their own.
/// A module not listed gets those.
final moduleEditors = <String, ModuleEditor>{
  appWidgetModule.name: appWidgetEditor,
  styleModule.name: styleEditor,
  layoutModule.name: layoutEditor,
  sizingModule.name: sizingEditor,
  scrollModule.name: scrollEditor,
  dockModule.name: dockEditor,
  triggersModule.name: triggersEditor,
  variablesModule.name: variablesEditor,
  prefabRulesModule.name: prefabRulesEditor,
  wallpaperModule.name: wallpaperEditor,
};

/// The body of [edit]'s section.
List<Widget> editModule(ModuleEdit edit) =>
    (moduleEditors[edit.type.name] ?? (edit) => edit.fields())(edit);
