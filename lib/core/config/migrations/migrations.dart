import 'dart:convert';

import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/config/migrations/v14_to_v15.dart';

export 'save_json.dart' show Device, Json;

/// The version of what is saved now: `config.json`, and a layout sent on
/// its own. Both say it as `v`.
///
/// To change what is saved in a way older saves do not already fit:
///
///  1. add a [Migration] from this version to the next at the end of
///     [migrations], with its rules in a file of their own beside the
///     others;
///  2. make this the version it goes to;
///  3. have the models read and write the new form only.
///
/// A step that has shipped is never changed: saves that went through it
/// are out there. What it got wrong, a later step puts right.
const saveVersion = 15;

/// The oldest version there are still steps from. A save from before it
/// cannot be brought up to date: the steps that did were taken out when
/// everything on the screen became one kind of thing, a component.
const oldestVersion = 14;

/// One thing a [Migration] does to a save, by changing [save] in place. It
/// finds what it is for and leaves the rest be, whatever shape that is in:
/// what is wrong with a save is for the models to say when they read it.
typedef Rule = void Function(Json save, Device device);

/// How a save of one version becomes one of the next.
class Migration {
  const Migration({
    required this.from,
    required this.to,
    required this.what,
    required this.rules,
    this.needsDevice = false,
  });

  final int from, to;

  /// What changed, in a line.
  final String what;

  /// Applied in the order given.
  final List<Rule> rules;

  /// True when a rule does better for knowing the [Device], which whoever
  /// loads a save may then wait for.
  final bool needsDevice;
}

/// Every change there has been to what is saved, oldest first. A save of
/// any version follows them from where it is to [saveVersion].
const migrations = [
  Migration(
    from: 14,
    to: 15,
    what:
        'Everything on the screen is a component, a pane among them, and '
        'a prefab is a component that was saved, with variants in place '
        'of layouts.',
    rules: [everythingAComponent, prefabsAsComponents],
  ),
];

/// The version [save] is: what it says, or failing that what its layout
/// says. One that says nothing is taken to be written as things are now.
int versionOf(Map<Object?, Object?> save) => switch (save) {
  {'v': final num version} => version.toInt(),
  {'layout': {'v': final num version}} => version.toInt(),
  _ => saveVersion,
};

/// The steps [save] has yet to go through.
Iterable<Migration> pending(Map<Object?, Object?> save) {
  final version = versionOf(save);
  return migrations.where((step) => step.from >= version);
}

/// Whether bringing [save] up to date goes better with the [Device] known.
bool needsDevice(Map<Object?, Object?> save) =>
    pending(save).any((step) => step.needsDevice);

/// [save], a whole config, as it is written now: a copy taken through every
/// step from its version to [saveVersion]. One that is there already, or
/// from a later version than this, is given back as it is.
///
/// Throws a [FormatException] where a rule cannot make sense of what it is
/// there to change, and for a save from before [oldestVersion].
Json migrate(Map<Object?, Object?> save, {Device device = Device.unknown}) {
  if (versionOf(save) < oldestVersion) {
    throw FormatException(
      'Saved by a version too old to read (${versionOf(save)})',
    );
  }
  final steps = pending(save).toList();
  if (steps.isEmpty) return save is Json ? save : save.cast();
  // A copy all of whose parts can be changed, whatever was handed in.
  final next = (jsonDecode(jsonEncode(save)) as Map).cast<String, Object?>();
  for (final step in steps) {
    for (final rule in step.rules) {
      rule(next, device);
    }
  }
  next['v'] = saveVersion;
  if (next['layout'] case final Json layout) layout['v'] = saveVersion;
  return next;
}

/// [layout], a layout on its own, as it is written now. It goes through
/// the same steps as the config it would be part of.
Json migrateLayout(
  Map<Object?, Object?> layout, {
  Device device = Device.unknown,
}) {
  final version = switch (layout['v']) {
    final num version => version.toInt(),
    _ => saveVersion,
  };
  if (version >= saveVersion) return layout is Json ? layout : layout.cast();
  return migrate({'v': version, 'layout': layout}, device: device)['layout']!
      as Json;
}
