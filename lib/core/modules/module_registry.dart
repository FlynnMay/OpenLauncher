import 'package:openlauncher/core/modules/app_widget_module.dart';
import 'package:openlauncher/core/modules/dock_module.dart';
import 'package:openlauncher/core/modules/focus_module.dart';
import 'package:openlauncher/core/modules/icon_module.dart';
import 'package:openlauncher/core/modules/layout_module.dart';
import 'package:openlauncher/core/modules/meter_module.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/modules/overlay_module.dart';
import 'package:openlauncher/core/modules/picture_module.dart';
import 'package:openlauncher/core/modules/prefab_rules_module.dart';
import 'package:openlauncher/core/modules/preview_module.dart';
import 'package:openlauncher/core/modules/scroll_module.dart';
import 'package:openlauncher/core/modules/sizing_module.dart';
import 'package:openlauncher/core/modules/slot_module.dart';
import 'package:openlauncher/core/modules/style_module.dart';
import 'package:openlauncher/core/modules/text_module.dart';
import 'package:openlauncher/core/modules/triggers_module.dart';
import 'package:openlauncher/core/modules/variables_module.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Every module, in the order the editor lists them. A new one goes here.
const moduleTypes = <ModuleType>[
  textModule,
  pictureModule,
  iconModule,
  meterModule,
  appWidgetModule,
  previewModule,
  styleModule,
  layoutModule,
  slotModule,
  sizingModule,
  scrollModule,
  dockModule,
  overlayModule,
  focusModule,
  triggersModule,
  variablesModule,
  prefabRulesModule,
];

final _byName = {for (final type in moduleTypes) type.name: type};

ModuleType? moduleNamed(String name) => _byName[name];

/// The modules that draw something.
Iterable<ModuleType> get visualModules =>
    moduleTypes.where((type) => type.visual);

extension NodeModules on Node {
  /// What it draws, if anything.
  ModuleType? get visual {
    for (final name in modules.keys) {
      if (_byName[name] case final type? when type.visual && has(name)) {
        return type;
      }
    }
    return null;
  }

  /// A node of its own that draws nothing: it holds and arranges others.
  bool get isContainer => !isInstance && visual == null;

  /// [key] of [type] as set, else that field's default.
  Object? valueOf(ModuleType type, String key) =>
      values(type.name)?[key] ??
      type.fields.where((field) => field.key == key).firstOrNull?.defaultValue;
}
