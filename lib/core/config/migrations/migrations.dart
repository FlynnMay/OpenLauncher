import 'dart:convert';

import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/config/migrations/v10_to_v11.dart';
import 'package:openlauncher/core/config/migrations/v1_to_v2.dart';
import 'package:openlauncher/core/config/migrations/v2_to_v3.dart';
import 'package:openlauncher/core/config/migrations/v3_to_v4.dart';
import 'package:openlauncher/core/config/migrations/v4_to_v5.dart';
import 'package:openlauncher/core/config/migrations/v5_to_v6.dart';
import 'package:openlauncher/core/config/migrations/v6_to_v7.dart';
import 'package:openlauncher/core/config/migrations/v7_to_v8.dart';
import 'package:openlauncher/core/config/migrations/v8_to_v9.dart';
import 'package:openlauncher/core/config/migrations/v9_to_v10.dart';

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
const saveVersion = 11;

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
    from: 1,
    to: 2,
    what:
        'Panels hold a pane in place of sections, sidebars are panels like '
        'any other, there can be several wallpapers, and hidden entities are '
        'removed ones.',
    rules: [
      wallpaperToWallpapers,
      orderToLayout,
      sectionsToPanes,
      sidebarsAsRows,
      hiddenToRemoved,
    ],
  ),
  Migration(
    from: 2,
    to: 3,
    what: 'Items, panes and folders go by ids that say what they are.',
    rules: [readableIds],
    needsDevice: true,
  ),
  Migration(
    from: 3,
    to: 4,
    what:
        'The quick actions are a popup of buttons in the layout, not a '
        'list of names beside it.',
    rules: [menuAsPanel],
  ),
  Migration(
    from: 4,
    to: 5,
    what:
        'How an entity is drawn is what it sets differently from its prefab, '
        'and what a pane makes of its entities is a rule for each prefab.',
    rules: [cardLooksAsOverrides, paneLooksAsRules],
  ),
  Migration(
    from: 5,
    to: 6,
    what:
        'A card is an instance of a prefab drawn from an entity, and says '
        'so; an action is done to an entity.',
    rules: [cardsAsInstances, prefabActsOnEntities],
  ),
  Migration(
    from: 6,
    to: 7,
    what:
        'The time, the date and what plays are entities, read by their '
        'ids, and the media player presents its own actions.',
    rules: [valuesAsEntities],
  ),
  Migration(
    from: 7,
    to: 8,
    what:
        'The clock, the weather and what plays are instances of prefabs '
        'drawn from their entities, not widgets of kinds of their own.',
    rules: [widgetsAsPrefabs],
  ),
  Migration(
    from: 8,
    to: 9,
    what:
        'What an instance is drawn from is one of its variables, as any '
        'component may have variables.',
    rules: [sourceAsVariable],
  ),
  Migration(
    from: 9,
    to: 10,
    what: 'A folder is opened by setting its variable `open`.',
    rules: [foldersOpenByVariable],
  ),
  Migration(
    from: 10,
    to: 11,
    what: 'What opens a folder is an instance of a prefab, drawn from it.',
    rules: [foldersAsInstances],
  ),
];

/// The version [save] is: what it says, or for a config from before
/// configs said, what its layout says. From before either did, the first.
int versionOf(Map<Object?, Object?> save) => switch (save) {
  {'v': final num version} => version.toInt(),
  {'layout': {'v': final num version}} => version.toInt(),
  _ => 1,
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
/// there to change.
Json migrate(Map<Object?, Object?> save, {Device device = Device.unknown}) {
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
    _ => 1,
  };
  if (version >= saveVersion) return layout is Json ? layout : layout.cast();
  return migrate({'v': version, 'layout': layout}, device: device)['layout']!
      as Json;
}
