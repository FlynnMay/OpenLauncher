import 'dart:convert';

import 'package:openlauncher/core/config/app_version.dart';
import 'package:openlauncher/core/config/migrations/save_json.dart';
import 'package:openlauncher/core/config/migrations/v1_to_v2.dart';
import 'package:openlauncher/core/config/migrations/v2_to_v3.dart';

export 'save_json.dart' show Device, Json;

/// The current save version, written as `v` on the config and the layout.
/// It counts changes to the saved format, not releases.
///
/// To change the saved format: add a [Migration] to the end of [migrations]
/// with its rules in a new file, bump this, and have the models read and
/// write only the new form. Never edit a shipped step.
const saveVersion = 3;

/// One in-place change to a save. Rules are JSON only; they never use the
/// models.
typedef Rule = void Function(Json save, Device device);

class Migration {
  const Migration({
    required this.from,
    required this.to,
    required this.since,
    required this.what,
    required this.rules,
    this.needsDevice = false,
  });

  final int from, to;

  /// The release it first shipped in, as in `0.2.0`.
  final String since;

  /// What changed, in a line.
  final String what;

  final List<Rule> rules;

  /// Whether a rule benefits from [Device] info.
  final bool needsDevice;
}

/// Every migration, oldest first. Version 1 is the format of release 0.1.0.
const migrations = <Migration>[
  Migration(
    from: 1,
    to: 2,
    since: '0.2.0',
    what: 'Force stop and automatic setup removed',
    rules: [withoutAdbActions],
  ),
  Migration(
    from: 2,
    to: 3,
    since: '0.2.0',
    what:
        'Operations named by address; feeds are sources; pack ids; quick '
        'actions as a prefab',
    rules: [operationsByAddress, feedsAsSources, packIds, quickActionsAsPrefab],
  ),
];

/// The version of [save], from it or its layout. A save with no version is
/// treated as current.
int versionOf(Map<Object?, Object?> save) => switch (save) {
  {'v': final num version} => version.toInt(),
  {'layout': {'v': final num version}} => version.toInt(),
  _ => saveVersion,
};

/// Whether [save] was written in a format newer than this release reads.
bool isNewer(Map<Object?, Object?> save) => versionOf(save) > saveVersion;

/// The steps [save] still needs.
Iterable<Migration> pending(
  Map<Object?, Object?> save, {
  List<Migration> steps = migrations,
}) {
  final version = versionOf(save);
  return steps.where((step) => step.from >= version);
}

bool needsDevice(Map<Object?, Object?> save) =>
    pending(save).any((step) => step.needsDevice);

/// [save] migrated to [saveVersion]; returned as is if already current.
///
/// Throws [FormatException] if a rule fails or the save [isNewer].
Json migrate(
  Map<Object?, Object?> save, {
  Device device = Device.unknown,
  List<Migration> steps = migrations,
}) {
  if (isNewer(save)) {
    throw FormatException(switch (save['app']) {
      final String app =>
        'Saved by OpenLauncher $app, newer than this one ($appVersion). '
            'Update to read it.',
      _ => 'Saved by a newer OpenLauncher. Update to read it.',
    });
  }
  final needed = pending(save, steps: steps).toList();
  if (needed.isEmpty) return save is Json ? save : save.cast();
  // A deep, mutable copy.
  final next = (jsonDecode(jsonEncode(save)) as Map).cast<String, Object?>();
  for (final step in needed) {
    for (final rule in step.rules) {
      rule(next, device);
    }
  }
  final version = needed.last.to;
  next['v'] = version;
  if (next['layout'] case final Json layout) layout['v'] = version;
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
  if (version == saveVersion) return layout is Json ? layout : layout.cast();
  return migrate({'v': version, 'layout': layout}, device: device)['layout']!
      as Json;
}
