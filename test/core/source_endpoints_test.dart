import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/registries/source_endpoint_registry.dart';
import 'package:openlauncher/editor/tv/tv.dart';

void main() {
  test('every address a pack reads from the launcher is registered', () {
    final named = _packJsonFiles().expand(_launcherAddressesIn).toSet();
    expect(named, isNotEmpty);
    expect(named.difference(launcherSourceEndpoints.keys.toSet()), isEmpty);
  });

  test('reading sources without the registry says what is missing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(sourceEndpointsProvider),
      throwsA(
        predicate((error) => '$error'.contains('sourceEndpointOverrides')),
      ),
    );
  });

  test('the editor registers the same endpoints as the launcher', () {
    final container = ProviderContainer(overrides: tvOverrides);
    addTearDown(container.dispose);
    expect(container.read(sourceEndpointsProvider), launcherSourceEndpoints);
  });
}

Iterable<File> _packJsonFiles() => Directory('packs')
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
