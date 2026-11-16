import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/packs/pack_store.dart';
import 'package:openlauncher/core/sources/pack_settings_of.dart';
import 'package:openlauncher/core/sources/source_rows.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/entity_action.dart';
import 'package:openlauncher_domain/entities/generator.dart';
import 'package:openlauncher_domain/sources/source.dart';

/// The entities of every pack: each pack's own, then what its generators
/// make. `pack:` pictures are given as files. A poll that changes nothing
/// gives the same list again, so nothing that reads it is rebuilt.
final packEntitiesProvider = AsyncNotifierProvider<PackEntities, List<Entity>>(
  PackEntities.new,
);

class PackEntities extends AsyncNotifier<List<Entity>> {
  @override
  Future<List<Entity>> build() async {
    final made = await _made();
    final before = state.value;
    return before != null && listEquals(before, made) ? before : made;
  }

  Future<List<Entity>> _made() async {
    final List<PackContents> packs;
    try {
      packs = await ref.watch(packContentsProvider.future);
    } on Object {
      return const [];
    }
    if (!ref.mounted) return const [];
    final picture = ref.watch(packPictureProvider);
    final settings = ref.watch(packSettingsOfProvider);
    // Every source watched before any is waited for.
    final rows = {
      for (final PackContents(:pack, :sources, :generators) in packs)
        for (final MapEntry(key: name, value: generator) in generators.entries)
          '${pack.id}/$name': _rowsOf(
            ref,
            pack.id,
            generator.from,
            sources[generator.from]!,
            settings[pack.id],
          ),
    };
    final made = <Entity>[];
    for (final PackContents(:pack, :entities, :sources, :generators) in packs) {
      for (final entity in [
        ...entities,
        for (final MapEntry(key: name, value: generator) in generators.entries)
          ...await _madeBy(
            generator,
            await rows['${pack.id}/$name']!,
            settings[pack.id] ?? const {},
            _defaultParams(sources[generator.from]!, settings[pack.id]),
          ),
      ]) {
        // A made id is the pack's like any other.
        if (!entity.id.startsWith('${pack.id}:')) continue;
        made.add(await _pictured(_fed(entity, pack.id, sources), picture));
      }
    }
    return made;
  }

  /// What [generator] makes of [rows]. The event loop turns once first, so a
  /// frame can be drawn between one generator's work and the next.
  Future<List<Entity>> _madeBy(
    Generator generator,
    List<Object?> rows,
    Map<String, Object?> settings,
    Map<String, Object?> params,
  ) async {
    await Future<void>.delayed(Duration.zero);
    return generator.entitiesFrom(rows, settings: settings, params: params);
  }

  /// The rows of source [name] asked with its default params; none while a
  /// required one has no value.
  Future<List<Object?>> _rowsOf(
    Ref ref,
    String pack,
    String name,
    Source source,
    Map<String, Object?>? settings,
  ) {
    final params = _defaultParams(source, settings);
    if (source.missing(params) != null) return Future.value(const []);
    return _rows(ref, (id: '$pack:$name', source: source.filled(params)));
  }

  /// What a source's params are when nobody gives any: their defaults.
  Map<String, Object?> _defaultParams(
    Source source,
    Map<String, Object?>? settings,
  ) => source.valuesOf(const {}, settings ?? const {});
}

/// [entity] with the pack source its feed names found, sharing its fetch.
Entity _fed(Entity entity, String pack, Map<String, Source> sources) {
  final feed = entity.feed;
  if (feed == null || feed.isAddress || feed.name == null) return entity;
  return switch (sources[feed.name]) {
    null => entity,
    final source => entity.copyWith(
      feed: Feed(
        feed.name!,
        inline: source.toJson(),
        shared: '$pack:${feed.name}',
      ),
    ),
  };
}

/// Nothing while a source cannot be read.
Future<List<Object?>> _rows(Ref ref, SourceAt at) async {
  try {
    return await ref.watch(sourceRowsProvider(at).future);
  } on Object {
    return const [];
  }
}

Future<Entity> _pictured(
  Entity entity,
  Future<String?> Function(String) picture,
) async {
  if (!entity.data.values.any(isPackPicture)) return entity;
  return entity.copyWith(
    data: {
      for (final MapEntry(:key, :value) in entity.data.entries)
        key: isPackPicture(value) ? await picture(value as String) : value,
    }..removeWhere((_, value) => value == null),
  );
}
