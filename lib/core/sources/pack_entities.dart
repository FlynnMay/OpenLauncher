import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/packs/pack_store.dart';
import 'package:openlauncher/core/sources/source.dart';
import 'package:openlauncher/core/sources/source_rows.dart';

/// The entities of the built-in packs (true) or the others: each pack's
/// own, then what its generators make. `pack:` pictures are given as files.
final packEntitiesProvider = FutureProvider.family<List<Entity>, bool>((
  ref,
  builtIn,
) async {
  final List<PackContents> packs;
  try {
    packs = await ref.watch(packContentsProvider.future);
  } on Object {
    return const [];
  }
  if (!ref.mounted) return const [];
  final picture = ref.watch(packPictureProvider);
  final ours = packs.where((contents) => contents.pack.builtIn == builtIn);
  // Every source watched before any is waited for.
  final rows = {
    for (final PackContents(:pack, :sources, :generators) in ours)
      for (final MapEntry(key: name, value: generator) in generators.entries)
        '${pack.id}/$name': _rows(ref, (
          id: '${pack.id}:${generator.from}',
          source: sources[generator.from]!,
        )),
  };
  final made = <Entity>[];
  for (final PackContents(:pack, :entities, :sources, :generators) in ours) {
    for (final entity in [
      ...entities,
      for (final MapEntry(key: name, value: generator) in generators.entries)
        ...generator.entitiesFrom(await rows['${pack.id}/$name']!),
    ]) {
      if (!builtIn && !entity.id.startsWith('${pack.id}:')) continue;
      made.add(await _pictured(_fed(entity, pack.id, sources), picture));
    }
  }
  return made;
});

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
