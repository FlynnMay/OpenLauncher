import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';

/// The body of a module's section in the inspector.
typedef ModuleEditor = List<Widget> Function(ModuleEdit edit);

/// One module of the selected nodes, and how to change it.
class ModuleEdit {
  ModuleEdit({
    required this.type,
    required List<Node> nodes,
    required this.parents,
    required this.send,
    this.onCommand,
    this.prefabs = const {},
    this.inPrefab = false,
    this.exposable = false,
    this.inDock = false,
    this.scope = const {},
  }) : on = [
         for (final node in nodes) !resolved(node, prefabs).isOff(type.name),
       ],
       _saved = nodes,
       nodes = [for (final node in nodes) _switchedOn(node, type)],
       drawn = [
         for (final node in nodes) _switchedOn(resolved(node, prefabs), type),
       ];

  final ModuleType type;

  /// As saved, and as drawn: an instance over its prefab. Shown with the
  /// module on, so one switched off still shows its values; changes go
  /// through [onChanged].
  final List<Node> nodes, drawn;

  /// Whether each has the module switched on.
  final List<bool> on;

  /// Their parents; none for a screen's root.
  final List<Node> parents;

  /// Does operations to nodes, by id, as one step.
  final void Function(Map<String, List<SliceOp>> opsByNode) send;

  /// Does a command that is not an edit of the nodes, such as making a
  /// container the inbox; null where there is no such thing to do.
  final void Function(Command command)? onCommand;

  /// As saved, with nothing switched on for show.
  final List<Node> _saved;

  final Map<String, Prefab> prefabs;

  /// Edited in an open prefab.
  final bool inPrefab;

  /// A prefab's root, whose variables instances can show.
  final bool exposable;

  /// In a docked node.
  final bool inDock;

  /// What its triggers can read from the nodes around it.
  final Variables scope;

  Node get node => nodes.first;
  Node get shown => drawn.first;
  bool get single => nodes.length == 1;
  Set<String> get ids => {for (final node in nodes) node.id};

  /// The first node's values as drawn, without the switch.
  late final ModuleValues values = {...?shown.modules[type.name]}
    ..remove(enabledKey);

  /// Keys whose values differ between the nodes.
  late final Set<String> mixed = {
    for (final key in {
      for (final node in drawn) ...?node.modules[type.name]?.keys,
    })
      if ({for (final node in drawn) jsonEncode(node.modules[type.name]?[key])}
              .length >
          1)
        key,
  };

  /// Whether the single instance's prefab has this module.
  late final bool inherited =
      single &&
      node.isInstance &&
      !type.instanceOwned &&
      resolved(node.withModule(type.name, null), prefabs).added(type.name);

  /// Keys the single instance sets over its prefab's.
  late final Set<String> own = inherited
      ? ({...?node.modules[type.name]?.keys}..remove(enabledKey))
      : const {};

  void _all(List<SliceOp> ops) => send({for (final id in ids) id: ops});

  /// Sets [key] on every node: an instance's over its prefab's.
  void set(String key, Object? value) =>
      _all([SetField(type.name, key, value)]);

  /// Takes the instance's own [key] away.
  void revert(String key) => revertAll([key]);

  /// Takes the instance's own [keys] away.
  void revertAll(List<String> keys) =>
      _all([for (final key in keys) RevertField(type.name, key)]);

  void switchTo({required bool on}) => _all([SwitchModule(type.name, on)]);

  void remove() => _all([RemoveModule(type.name)]);

  void add() => _all([AddModule(type.name)]);

  /// Changes each node as [how] says, as the modules that come out different.
  void onChanged(Node Function(Node node) how) => send({
    for (final node in _saved) node.id: moduleOpsBetween(node, how(node)),
  });

  /// Generated fields for [fields], the module's own by default.
  List<Widget> fields([List<Field>? fields]) => ruleFields(
    options: fields ?? type.fields,
    json: values,
    mixed: mixed,
    marked: own,
    onRevert: revert,
    onChanged: set,
  );
}

Node _switchedOn(Node node, ModuleType type) =>
    node.isOff(type.name) ? node.withValue(type.name, enabledKey, null) : node;
