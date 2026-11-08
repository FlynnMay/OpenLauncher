import 'dart:convert';

import 'package:openlauncher_domain/config/app_version.dart';
import 'package:openlauncher_domain/config/migrations/save_json.dart';
import 'package:openlauncher_domain/config/migrations/v1_to_v2.dart';
import 'package:openlauncher_domain/config/migrations/v2_to_v3.dart';
import 'package:openlauncher_domain/config/migrations/v2_to_v3_overlays.dart';
import 'package:openlauncher_domain/config/migrations/v2_to_v3_panes.dart';
import 'package:openlauncher_domain/config/migrations/v2_to_v3_slots.dart';
import 'package:openlauncher_domain/config/migrations/v2_to_v3_visibility.dart';
import 'package:openlauncher_domain/config/migrations/v3_to_v4.dart';

export 'package:openlauncher_domain/config/migrations/save_json.dart'
    show Device, Json;

/// Counts format changes, not releases. To change the format, add a
/// [Migration] and bump this; never change what a shipped step does.
const saveVersion = 4;

/// JSON only; never uses the models.
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

  final int from;
  final int to;

  final String since;

  final String what;

  final List<Rule> rules;

  final bool needsDevice;

  void apply(Json save, Device device) {
    for (final rule in rules) {
      rule(save, device);
    }
  }
}

/// Version 1 is release 0.1.0's format.
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
        'actions as a prefab; folders and sidebars record their template; '
        'docked panes say whether a press closes them; nodes with '
        'modules; folders and sidebars are instances holding what is in them; '
        'nothing docks inline; panes write out their box, and one with a '
        'heading is a Section; layers are gone, screens and Overlays take '
        'their place; visibility is a module every node has',
    rules: [
      operationsByAddress,
      feedsAsSources,
      packIds,
      quickActionsAsPrefab,
      templatesRecorded,
      closeOnPressRecorded,
      nodesAndModules,
      templatesLinked,
      inlineDocksCentred,
      panelsWrittenOut,
      overlaysForLayers,
      visibilityAsModule,
    ],
  ),
  Migration(
    from: 3,
    to: 4,
    since: '0.3.0',
    what: 'Closing a popup is closing an overlay',
    rules: [popupCloseAsOverlayClose],
  ),
];

/// A save with no version is current.
int versionOf(Map<Object?, Object?> save) => switch (save) {
  {'v': final num version} => version.toInt(),
  {'layout': {'v': final num version}} => version.toInt(),
  _ => saveVersion,
};

bool isNewer(Map<Object?, Object?> save) => versionOf(save) > saveVersion;

Iterable<Migration> pending(
  Map<Object?, Object?> save, {
  List<Migration> steps = migrations,
}) {
  final version = versionOf(save);
  return steps.where((step) => step.from >= version);
}

bool needsDevice(Map<Object?, Object?> save) =>
    pending(save).any((step) => step.needsDevice);

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
  if (needed.isEmpty) return jsonObject(save);
  final next = _deepCopy(save);
  for (final step in needed) {
    step.apply(next, device);
  }
  final version = needed.last.to;
  next['v'] = version;
  if (next['layout'] case final Json layout) layout['v'] = version;
  return next;
}

Json _deepCopy(Map<Object?, Object?> json) =>
    jsonObject(jsonDecode(jsonEncode(json)));

Json migrateLayout(
  Map<Object?, Object?> layout, {
  Device device = Device.unknown,
}) {
  final version = switch (layout['v']) {
    final num version => version.toInt(),
    _ => saveVersion,
  };
  if (version == saveVersion) return jsonObject(layout);
  return migrate({'v': version, 'layout': layout}, device: device)['layout']!
      as Json;
}
