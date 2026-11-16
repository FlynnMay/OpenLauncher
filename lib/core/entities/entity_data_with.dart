import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/sources/pack_settings_of.dart';
import 'package:openlauncher/core/sources/source_rows.dart';
import 'package:openlauncher_domain/entities/generator.dart';

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
    final packs = ref.watch(packContentsProvider).value;
    final settings = ref.watch(packSettingsOfProvider);
    if (packs == null) return null;
    final args = (jsonDecode(call.args) as Map).cast<String, Object?>();
    for (final contents in packs) {
      for (final generator in contents.generators.values) {
        if (!generator.makes(call.id)) continue;
        final source = contents.sources[generator.from];
        if (source == null) return null;
        final plain = settings[contents.pack.id] ?? const {};
        final params = source.valuesOf(args, plain);
        if (source.missing(params) != null) return null;
        final rows = ref.watch(
          sourceRowsProvider((
            id: '${contents.pack.id}:${generator.from}#${call.args}',
            source: source.filled(params),
          )),
        );
        return _entityOf(generator, rows.value, plain, params, call.id);
      }
    }
    return null;
  },
);

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
