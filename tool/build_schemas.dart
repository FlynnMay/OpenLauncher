// Writes the JSON Schemas pack files are checked by into schemas/. They are
// published from there, and a test fails when they are out of date:
// dart run tool/build_schemas.dart

import 'dart:io';

import 'package:openlauncher_domain/schema/pack_schemas.dart';

const _to = 'schemas';

void main() {
  final out = Directory(_to)..createSync(recursive: true);
  final schemas = packSchemas();
  for (final old in out.listSync().whereType<File>()) {
    if (!schemas.containsKey(old.uri.pathSegments.last)) old.deleteSync();
  }
  for (final MapEntry(key: file, value: schema) in schemas.entries) {
    File('$_to/$file').writeAsStringSync(schemaText(schema));
    stdout.writeln('Schema: $file');
  }
}
