import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// A module's saved values: field key -> value.
typedef ModuleValues = Map<String, Object?>;

/// The key that switches a module off when false. Reserved in every module,
/// so no variable, trigger or prefab rule may be called this.
const enabledKey = 'enabled';

/// Whether [values] are switched off.
bool switchedOff(ModuleValues? values) => values?[enabledKey] == false;

/// [over] merged onto [under], key by key; null removes a key.
ModuleValues mergeValues(ModuleValues under, ModuleValues over) =>
    {...under, ...over}..removeWhere((_, value) => value == null);

/// Where a module means something.
enum ModuleUse {
  anywhere,

  /// On a prefab's part.
  inPrefab,

  /// On the screen, outside any prefab.
  onScreen,

  /// On a screen's root.
  screenRoot,
}

/// Machinery a node takes on: what it draws, how it arranges its children,
/// how it is styled, docked, focused or pressed. A node's modules decide what
/// it is.
@immutable
class ModuleType {
  const ModuleType(
    this.name,
    this.label, {
    this.visual = false,
    this.fields = const [],
    this.styleKeys = const [],
    this.instanceOwned = false,
    this.size = (1, 1),
    this.starter = const {},
    this.needs = const [],
    this.use = ModuleUse.anywhere,
    this.inLayout = false,
    this.mandatory = false,
  });

  /// Its key in a node's `modules`.
  final String name;

  final String label;

  /// Draws something. A node has at most one visual module.
  final bool visual;

  /// Its settings; the editor's form is generated from these.
  final List<Field> fields;

  /// Style properties it draws with, beyond the box ones.
  final List<String> styleKeys;

  /// On an instance only the instance's own values count, not its prefab's.
  final bool instanceOwned;

  /// Size in cells of a new node with it.
  final (int, int) size;

  /// Values a new one starts with.
  final ModuleValues starter;

  /// Modules it works through, by name; adding it adds them.
  final List<String> needs;

  final ModuleUse use;

  /// Only means something on a child of a node with a Layout.
  final bool inLayout;

  /// Every node has it: always listed, never added, removed or switched off.
  final bool mandatory;

  /// With no values it says nothing, so it is left out of a save and need not
  /// be kept.
  bool get nothingWhenEmpty => mandatory || inLayout;

  /// [under] (a prefab's) with [over] (an instance's or an override's)
  /// applied.
  ModuleValues merge(ModuleValues under, ModuleValues over) =>
      mergeValues(under, over);
}
