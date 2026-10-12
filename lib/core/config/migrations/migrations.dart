import 'dart:convert';

import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/config/migrations/v14_to_v15.dart';
import 'package:openlauncher/core/config/migrations/v15_to_v16.dart';
import 'package:openlauncher/core/config/migrations/v16_to_v17.dart';
import 'package:openlauncher/core/config/migrations/v17_to_v18.dart';
import 'package:openlauncher/core/config/migrations/v18_to_v19.dart';
import 'package:openlauncher/core/config/migrations/v19_to_v20.dart';
import 'package:openlauncher/core/config/migrations/v20_to_v21.dart';

export 'save_json.dart' show Device, Json;

/// The current save version, written as `v` on the config and the layout.
///
/// To change the saved format: add a [Migration] to the end of [migrations]
/// with its rules in a new file, bump this, and have the models read and
/// write only the new form. Never edit a shipped step.
const saveVersion = 21;

/// The oldest version that can still be migrated.
const oldestVersion = 14;

/// One in-place change to a save. Rules are JSON only; they never use the
/// models.
typedef Rule = void Function(Json save, Device device);

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

  final List<Rule> rules;

  /// Whether a rule benefits from [Device] info.
  final bool needsDevice;
}

/// Every migration, oldest first.
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
  Migration(
    from: 15,
    to: 16,
    what:
        'Every action is some entity\'s: the quick actions are opened by '
        'their variables, and what is removed is named to the layout.',
    rules: [actionsOwned],
  ),
  Migration(
    from: 16,
    to: 17,
    what:
        'A variable says what sort of thing it holds; one that stands for '
        'an entity says so.',
    rules: [variablesTyped],
  ),
  Migration(
    from: 17,
    to: 18,
    what:
        'Every action names the entity that does it; one that names none '
        'is declined.',
    rules: [actionsTargeted],
  ),
  Migration(
    from: 18,
    to: 19,
    what:
        'The layout is a list of layers, the home screen at the bottom; a '
        'sidebar or a folder is a docked pane in it, with what it does '
        'when shown written on it.',
    rules: [panelsToLayers, layoutOfALayer, folderPictures],
  ),
  Migration(
    from: 19,
    to: 20,
    what:
        'A value the user made is an entity like any other, saved whole: '
        'what it reads is its feed or its data.',
    rules: [sourcesToEntities],
  ),
  Migration(
    from: 20,
    to: 21,
    what:
        'An icon is named by the set it is from, as in material:home; the '
        'sets come in packs.',
    rules: [iconsNamedBySet],
  ),
];

/// The version of [save], from it or its layout. A save with no version is
/// treated as current.
int versionOf(Map<Object?, Object?> save) => switch (save) {
  {'v': final num version} => version.toInt(),
  {'layout': {'v': final num version}} => version.toInt(),
  _ => saveVersion,
};

/// The steps [save] still needs.
Iterable<Migration> pending(Map<Object?, Object?> save) {
  final version = versionOf(save);
  return migrations.where((step) => step.from >= version);
}

bool needsDevice(Map<Object?, Object?> save) =>
    pending(save).any((step) => step.needsDevice);

/// [save] migrated to [saveVersion]; returned as is if already current.
///
/// Throws [FormatException] if a rule fails or the save is older than
/// [oldestVersion].
Json migrate(Map<Object?, Object?> save, {Device device = Device.unknown}) {
  if (versionOf(save) < oldestVersion) {
    throw FormatException(
      'Saved by a version too old to read (${versionOf(save)})',
    );
  }
  final steps = pending(save).toList();
  if (steps.isEmpty) return save is Json ? save : save.cast();
  // A deep, mutable copy.
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

/// The same for a layout sent on its own.
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
