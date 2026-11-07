import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';

/// Adds, replaces and removes prefabs by id, each whole, so an editor changing
/// one prefab leaves the others as another editor left them.
class ChangePrefabs extends Command {
  const ChangePrefabs({this.upserted = const [], this.removed = const []});

  /// What changes from one list of prefabs, as JSON, to another.
  factory ChangePrefabs.turning(List<Object?> from, List<Object?> into) {
    final before = _byId(from), after = _byId(into);
    return ChangePrefabs(
      upserted: [
        for (final MapEntry(:key, :value) in after.entries)
          if (!jsonEquals(before[key], value)) value,
      ],
      removed: [
        for (final id in before.keys)
          if (!after.containsKey(id)) id,
      ],
    );
  }

  factory ChangePrefabs.fromJson(Json json) => ChangePrefabs(
    upserted: [
      for (final prefab in jsonOptional<List<Object?>>(json, 'upserted') ?? [])
        jsonObject(prefab),
    ],
    removed: [
      for (final id in jsonOptional<List<Object?>>(json, 'removed') ?? [])
        if (id is String) id,
    ],
  );

  static const typeName = 'prefab.change';
  static const settingName = 'prefabs';

  final List<Json> upserted;
  final List<String> removed;

  bool get isEmpty => upserted.isEmpty && removed.isEmpty;

  @override
  String get type => typeName;

  @override
  Document edit(Document document) {
    final prefabs = [
      for (final prefab in _prefabsIn(document))
        if (!removed.contains(prefab['id']))
          upserted.firstWhere(
            (changed) => changed['id'] == prefab['id'],
            orElse: () => prefab,
          ),
    ];
    final present = {for (final prefab in prefabs) prefab['id']};
    return document.copyWith(
      settings: {
        ...document.settings,
        settingName: [
          ...prefabs,
          for (final prefab in upserted)
            if (!present.contains(prefab['id'])) prefab,
        ],
      },
    );
  }

  @override
  Command undoing(Document before) {
    final was = _byId(_prefabsIn(before));
    return ChangePrefabs(
      upserted: [
        for (final id in [...removed, ...upserted.map((p) => '${p['id']}')])
          ?was[id],
      ],
      removed: [
        for (final prefab in upserted)
          if (!was.containsKey(prefab['id'])) '${prefab['id']}',
      ],
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'upserted': upserted,
    'removed': removed,
  };

  static List<Json> _prefabsIn(Document document) => [
    for (final prefab in document.settings[settingName] as List? ?? const [])
      jsonObject(prefab),
  ];

  static Map<String, Json> _byId(List<Object?> prefabs) => {
    for (final prefab in prefabs)
      if (jsonObject(prefab) case {'id': final String id} when true)
        id: jsonObject(prefab),
  };
}

final Map<String, CommandReader> prefabCommandReaders = {
  ChangePrefabs.typeName: ChangePrefabs.fromJson,
};
