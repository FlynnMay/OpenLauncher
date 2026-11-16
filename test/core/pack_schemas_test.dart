import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:openlauncher/core/packs/pack_layout.dart';
import 'package:openlauncher_domain/json/json_decode.dart';
import 'package:openlauncher_domain/schema/pack_schemas.dart';
import 'package:openlauncher_domain/schema/schema_parts.dart' show commonFile;

/// [file]'s schema with the shared pieces put inside it, so it can be checked
/// without fetching [commonFile].
Map<String, Object?> bundled(String file) {
  final schemas = packSchemas();
  final own = Map<String, Object?>.from(
    _withoutCommonFile(schemas[file]!) as Map,
  );
  final shared = _withoutCommonFile(schemas[commonFile]!) as Map;
  return {
    ...own,
    r'$defs': {
      if (own[r'$defs'] case final Map defs) ...defs,
      ...shared[r'$defs'] as Map,
    },
  }..remove(r'$id');
}

Object? _withoutCommonFile(Object? json) => switch (json) {
  final Map map => {
    for (final MapEntry(:key, :value) in map.entries)
      key: key == r'$ref'
          ? (value as String).replaceFirst(commonFile, '')
          : _withoutCommonFile(value),
  },
  final List list => [for (final item in list) _withoutCommonFile(item)],
  _ => json,
};

JsonSchema schemaOf(String file) => JsonSchema.create(bundled(file));

/// What is wrong with [json] against [file]'s schema, one line each. A file
/// of one thing is also checked as that thing, which says where.
List<String> problemsOf(String file, Object? json) {
  final problems = _errorsOf(schemaOf(file), json);
  final one = bundled(file)[r'$defs'] as Map;
  if (problems.isEmpty || !one.containsKey('one')) return problems;
  final inside = JsonSchema.create({...bundled(file), r'$ref': r'#/$defs/one'});
  return [...problems, ..._errorsOf(inside, json)];
}

List<String> _errorsOf(JsonSchema schema, Object? json) => [
  for (final error in schema.validate(json).errors)
    '${error.instancePath}: ${error.message}'
        .split('\n')
        .first
        .substring(
          0,
          '${error.instancePath}: ${error.message}'
              .split('\n')
              .first
              .length
              .clamp(0, 200),
        ),
];

Object? readPackFile(File file) =>
    decodeJson(file.readAsStringSync(), source: file.path);

void main() {
  test('the schemas written to schemas/ are the ones the code makes', () {
    for (final MapEntry(key: file, value: schema) in packSchemas().entries) {
      expect(
        File('schemas/$file').readAsStringSync(),
        schemaText(schema),
        reason: '$file is out of date: dart run tool/build_schemas.dart',
      );
    }
    final written = Directory('schemas')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .toSet();
    expect(written, packSchemas().keys.toSet());
  });

  test('every schema is a schema', () {
    for (final file in packSchemas().keys) {
      expect(() => schemaOf(file), returnsNormally, reason: file);
    }
  });

  group('the system pack', () {
    final root = Directory('packs/system');
    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => (file, file.path.substring(root.path.length + 1)))
        .where((entry) => isJsonPath(entry.$2))
        .toList();

    test('is found', () => expect(files, isNotEmpty));

    for (final (file, path) in files) {
      final kind = PackFile.of(path)?.kind;
      final schemaFile = switch (path) {
        'pack.json' || 'pack.jsonc' => packManifestSchemaFile,
        _ when PackFile.isPackDefs(path) => defsSchemaFile,
        _ when PackFile.defsFeatureOf(path) != null => defsSchemaFile,
        _ when kind != null => schemaFileOf(kind),
        _ => null,
      };
      if (schemaFile == null) continue;
      test('$path is a ${schemaFile.split('.').first}', () {
        expect(problemsOf(schemaFile, readPackFile(file)), isEmpty);
      });
    }
  });

  group('a pack file', () {
    test('may use a chunk in place of what it requires', () {
      final prefab = {
        r'$use': 'card',
        'root': {'id': 'root'},
      };
      expect(problemsOf('prefab.schema.json', prefab), isEmpty);
    });

    test('is refused for a key nothing reads', () {
      final prefab = {
        'id': 'card',
        'root': {'id': 'root', 'colour': 'red'},
      };
      expect(problemsOf('prefab.schema.json', prefab), isNotEmpty);
    });

    test('is refused for a value of the wrong kind', () {
      final prefab = {
        'id': 'card',
        'root': {
          'id': 'root',
          'modules': {
            'layout': {'mode': 'sideways'},
          },
        },
      };
      expect(problemsOf('prefab.schema.json', prefab), isNotEmpty);
    });

    test('may name its schema', () {
      final entity = {r'$schema': schemaUrlOf(PackKind.entity), 'id': 'clock'};
      expect(problemsOf('entity.schema.json', entity), isEmpty);
      expect(jsonEncode(entity), contains('entity.schema.json'));
    });

    test('may hold several by name', () {
      final entities = {
        'clock': {'id': 'clock'},
        'date': {'id': 'date', 'label': 'Date'},
      };
      expect(problemsOf('entity.schema.json', entities), isEmpty);
    });
  });
}
