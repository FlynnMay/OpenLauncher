import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';

void main() {
  ProviderContainer containerOf(Map<String, String> files) {
    final container = ProviderContainer(
      overrides: [
        packsProvider.overrideWith(
          (ref) async => [
            Pack(id: 'hub', name: 'Hub', files: files.keys.toList()),
          ],
        ),
        packReaderProvider.overrideWith(
          (ref) =>
              (pack, path) async =>
                  files[path] == null ? null : utf8.encode(files[path]!),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'a pack that cannot be read is reported with its file and line',
    () async {
      final container = containerOf({'lights/entity.jsonc': '{ "id": '});
      final errors = await container.read(packLoadErrorsProvider.future);
      expect(errors.keys, ['hub']);
      expect(errors['hub'], contains('lights/entity.jsonc:1'));
      expect(await container.read(packContentsProvider.future), isEmpty);
    },
  );

  test('a pack that reads has no error', () async {
    final container = containerOf({
      'lights/entity.jsonc': '{ "id": "lamp", "label": "Lamp" }',
    });
    expect(await container.read(packLoadErrorsProvider.future), isEmpty);
    expect(await container.read(packContentsProvider.future), hasLength(1));
  });

  test('a pack is outside its support when written for a newer release', () {
    const pack = Pack(id: 'hub', name: 'Hub', app: '0.3.0');
    expect(pack.supportedBy('0.2.0'), isFalse);
    expect(pack.supportedBy('0.3.0'), isTrue);
  });
}
