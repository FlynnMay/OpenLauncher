import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/sources/asked_source_id.dart';
import 'package:openlauncher/core/sources/pack_settings_of.dart';
import 'package:openlauncher/core/sources/source_rows.dart';
import 'package:openlauncher_domain/entities/generator.dart';
import 'package:openlauncher_domain/sources/source.dart';

/// An entity asked for with arguments: its id, and the arguments as JSON so
/// the same ones are the same key.
typedef EntityWith = ({String id, String args});

/// What `{{<id>...}}` reads for a generated entity when its source is asked
/// with arguments: the same entity the generator makes, from the answer to
/// that request. Cards that ask the same share one fetch, and it stops when
/// none shows it. Null while the answer is not in, or if no generator makes
/// the entity.
final entityDataWithProvider = Provider.autoDispose.family<Object?, EntityWith>(
  (ref, call) {
    final packs = ref.watch(packContentsProvider).value ?? const [];
    final settings = ref.watch(packSettingsOfProvider);
    final maker = _makerOf(packs, call.id);
    if (maker == null) return null;
    final (:contents, :generator) = maker;
    final pack = contents.pack.id;
    final args = (jsonDecode(call.args) as Map).cast<String, Object?>();
    final plain = settings[pack] ?? const <String, Object?>{};
    final source = contents.sources[generator.from];
    final asked = source?.askedWith(args, plain);
    if (source == null || asked == null) return null;
    final rows = ref.watch(
      sourceRowsProvider((
        id: _requestId(
          pack,
          generator.from,
          asked,
          source.askedWith(const {}, plain),
        ),
        source: asked.request,
      )),
    );
    return _entityOf(generator, rows.value, plain, asked.params, call.id);
  },
);

/// What the fetch of [asked] is known by. Named for the values it asks with,
/// not the arguments as they were given, so the same request written another
/// way is the same fetch; and the pack's own when it asks with the defaults,
/// which the entity list already fetches.
String _requestId(
  String pack,
  String source,
  AskedSource asked,
  AskedSource? byDefault,
) =>
    byDefault != null &&
        jsonEncode(byDefault.params) == jsonEncode(asked.params)
    ? '$pack:$source'
    : AskedSourceId(pack, source, asked.params).text;

/// The generator that makes entity [id], and the pack it is in.
({PackContents contents, Generator generator})? _makerOf(
  List<PackContents> packs,
  String id,
) {
  for (final contents in packs) {
    final generator = contents.generators.values
        .where((one) => one.makes(id))
        .firstOrNull;
    if (generator != null) return (contents: contents, generator: generator);
  }
  return null;
}

Object? _entityOf(
  Generator generator,
  List<Object?>? rows,
  Map<String, Object?> settings,
  Map<String, Object?> params,
  String id,
) {
  if (rows == null) return null;
  final made = generator.entitiesFrom(rows, settings: settings, params: params);
  final entity = made.where((one) => one.id == id).firstOrNull;
  return entity == null ? null : entityDataFrom(entity, null);
}
