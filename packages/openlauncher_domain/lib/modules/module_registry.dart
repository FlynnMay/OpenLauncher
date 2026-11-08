import 'package:openlauncher_domain/modules/appearance/style_module.dart';
import 'package:openlauncher_domain/modules/appearance/visibility_module.dart';
import 'package:openlauncher_domain/modules/content/app_widget_module.dart';
import 'package:openlauncher_domain/modules/content/icon_module.dart';
import 'package:openlauncher_domain/modules/content/meter_module.dart';
import 'package:openlauncher_domain/modules/content/picture_module.dart';
import 'package:openlauncher_domain/modules/content/preview_module.dart';
import 'package:openlauncher_domain/modules/content/text_module.dart';
import 'package:openlauncher_domain/modules/layout/layout_module.dart';
import 'package:openlauncher_domain/modules/layout/scroll_module.dart';
import 'package:openlauncher_domain/modules/layout/sizing_module.dart';
import 'package:openlauncher_domain/modules/layout/slot_module.dart';
import 'package:openlauncher_domain/modules/logic/prefab_rules_module.dart';
import 'package:openlauncher_domain/modules/logic/triggers_module.dart';
import 'package:openlauncher_domain/modules/logic/variables_module.dart';
import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/modules/surface/dock_module.dart';
import 'package:openlauncher_domain/modules/surface/focus_module.dart';
import 'package:openlauncher_domain/modules/surface/overlay_module.dart';
import 'package:openlauncher_domain/modules/surface/wallpaper_module.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// Every module, in the order the editor lists them. A new one goes here.
const moduleTypes = <ModuleType>[
  visibilityModule,
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
  wallpaperModule,
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
