import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

void main() {
  late OperationsRegistry registry;

  setUp(() {
    final container = ProviderContainer(
      overrides: [
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(const [], const []),
        ),
      ],
    );
    addTearDown(container.dispose);
    registry = container.read(operationsRegistryProvider);
  });

  // Addresses are written out in full in data, so they are listed in full
  // here: renaming one is a decision, not a side effect.
  test('every operation there is, by its full address', () {
    expect(registry.all.map((operation) => operation.address).toSet(), {
      'os://apps/launch',
      'os://apps/info',
      'os://apps/uninstall',
      'os://inputs/switch',
      'os://media/command',
      'os://access/change',
      'os://settings/open',
      'launcher://layout/add',
      'launcher://layout/remove',
      'launcher://overlay/open',
      'launcher://overlay/close',
      'launcher://screen/open',
      'launcher://screen/back',
      'launcher://screen/add',
      'launcher://screen/remove',
      'launcher://screen/rename',
      'launcher://screen/duplicate',
      'launcher://screen/startup',
      'launcher://settings/open',
      'launcher://sources/fetch',
      'launcher://updates/check',
      'launcher://updates/install',
      'launcher://variables/set',
    });
  });

  test('every address a pack runs is an operation', () {
    final run = RegExp(r'"run"\s*:\s*"([a-z]+://[^"{]+)"');
    final missing = <String>[];
    for (final file in Directory('packs').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      for (final match in run.allMatches(file.readAsStringSync())) {
        final address = match.group(1)!;
        if (registry[address] == null) missing.add('$address in ${file.path}');
      }
    }
    expect(missing, isEmpty);
  });
}
