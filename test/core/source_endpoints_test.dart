import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/sources/source_endpoint_registry.dart';

void main() {
  test('every address a pack reads from the launcher is registered', () {
    final named = _packJsonFiles().expand(_launcherAddressesIn).toSet();
    expect(named, isNotEmpty);
    expect(named.difference(sourceEndpointRegistry.keys.toSet()), isEmpty);
  });
}

Iterable<File> _packJsonFiles() =>
    Directory('packs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'));

/// The `os://` and `launcher://` areas an entity feed or a source url names.
Iterable<String> _launcherAddressesIn(File file) {
  final json = jsonDecode(file.readAsStringSync());
  if (json is! Map) return const [];
  return [json['feed'], json['url']]
      .whereType<String>()
      .map(Uri.tryParse)
      .whereType<Uri>()
      .where((uri) => uri.isScheme('os') || uri.isScheme('launcher'))
      .map((uri) => '${uri.scheme}://${uri.host}');
}
