import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/entity_node.dart';

void main() {
  // Every entity the System pack writes, and the entities its generators
  // make, go through a node and come out as they were.
  Iterable<Map<String, Object?>> written() sync* {
    for (final file in Directory('packs/system').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) continue;
      if (file.path.endsWith('entity.json')) yield json;
      final made = json['entity'];
      if (file.path.endsWith('generator.json') &&
          made is Map<String, Object?>) {
        yield made;
      }
    }
  }

  test('the System pack has entities to check', () {
    expect(written().length, greaterThan(6));
  });

  test('a node writes back the entity JSON it was read from', () {
    for (final json in written()) {
      final node = nodeFromEntityJson(json)!;
      expect(
        entityJsonOf(node),
        Entity.fromJson(json)!.toJson(),
        reason: '${json['id']}',
      );
    }
  });
}
