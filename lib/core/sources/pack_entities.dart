import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/packs/pack_secrets.dart';
import 'package:openlauncher/core/packs/pack_store.dart';
import 'package:openlauncher/core/sources/pack_settings_of.dart';
import 'package:openlauncher/core/sources/source_rows.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/entity_action.dart';
import 'package:openlauncher_domain/entities/generator.dart';
import 'package:openlauncher_domain/sources/source.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

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
    final packGenerators = [
      for (final contents in packs) ..._generatorsOf(contents),
    ];
    final asked = {
      for (final packGenerator in packGenerators)
        packGenerator.key: packGenerator.source.askedWith(
          const {},
          settings[packGenerator.pack.id] ?? const {},
        ),
    };
    // Every source watched before any is waited for.
    final rows = {
      for (final packGenerator in packGenerators)
        packGenerator.key: _rowsOfGenerator(
          ref,
          packGenerator,
          asked[packGenerator.key],
        ),
    };
    final made = <Entity>[];
    for (final contents in packs) {
      final entities = [
        ...contents.entities,
        ...await _madeBy(contents, rows, asked, settings[contents.pack.id]),
      ];
      // A made id is the pack's like any other.
      final own = entities.where(
        (entity) => entity.id.startsWith('${contents.pack.id}:'),
      );
      for (final entity in own) {
        final fed = _fed(entity, contents.pack.id, contents.sources);
        made.add(await _pictured(fed, picture));
      }
    }
    return made;
  }

  /// What the generators of [contents] make of their rows. The event loop
  /// turns once before each, so a frame can be drawn between one generator's
  /// work and the next.
  Future<List<Entity>> _madeBy(
    PackContents contents,
    Map<String, Future<List<Object?>>> rows,
    Map<String, AskedSource?> asked,
    Map<String, Object?>? settings,
  ) async {
    final made = <Entity>[];
    for (final packGenerator in _generatorsOf(contents)) {
      final generatorRows = await rows[packGenerator.key]!;
      await Future<void>.delayed(Duration.zero);
      made.addAll(
        packGenerator.generator.entitiesFrom(
          generatorRows,
          settings: settings ?? const {},
          params: asked[packGenerator.key]?.params ?? const {},
        ),
      );
    }
    return made;
  }

  /// The rows of what [packGenerator] reads, as it was [asked]. None when it cannot
  /// be asked yet: a required param has no value, or the pack of a web source
  /// is not set up. Asking could only fail, and a source that failed once can
  /// be left waiting when the settings change.
  Future<List<Object?>> _rowsOfGenerator(
    Ref ref,
    _PackGenerator packGenerator,
    AskedSource? asked,
  ) {
    final settings = ref.watch(packSettingsOfProvider)[packGenerator.pack.id];
    final cannotAsk =
        asked == null ||
        !packGenerator.source.answeredHere &&
            _isNotSetUp(ref, packGenerator.pack, settings);
    return cannotAsk
        ? Future.value(const [])
        : _rows(ref, (id: packGenerator.sourceId, source: asked.request));
  }

  /// Whether a setting [pack] requires has no value yet. Secrets still being
  /// read count as not given, and the build is made again when they are.
  bool _isNotSetUp(Ref ref, Pack pack, Map<String, Object?>? settings) {
    final Map<String, String> secrets = pack.hasSecrets
        ? (ref.watch(packSecretsProvider).value?[pack.id] ?? const {})
        : const {};
    return pack.missing(settings ?? const {}, {
      for (final MapEntry(:key, :value) in secrets.entries)
        if (value.isNotEmpty) key,
    }).isNotEmpty;
  }
}

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

/// One generator of a pack and the source it reads.
class _PackGenerator {
  const _PackGenerator(this.contents, this.name, this.generator);

  final PackContents contents;
  final String name;
  final Generator generator;

  Pack get pack => contents.pack;
  Source get source => contents.sources[generator.from]!;

  /// What this generator is known by.
  String get key => '${pack.id}/$name';

  /// What its source's fetch is known by, shared by every reader.
  String get sourceId => '${pack.id}:${generator.from}';
}

Iterable<_PackGenerator> _generatorsOf(PackContents contents) => [
  for (final MapEntry(:key, :value) in contents.generators.entries)
    _PackGenerator(contents, key, value),
];

/// How long the entity list waits for one source: a little over its fetch's.
const _longestWait = Duration(seconds: 20);

/// Nothing while a source cannot be read.
Future<List<Object?>> _rows(Ref ref, SourceAt at) async {
  try {
    return await ref.watch(sourceRowsProvider(at).future).timeout(_longestWait);
  } on Object {
    return const [];
  }
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
