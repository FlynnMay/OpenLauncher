import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';

import '../support/packs.dart';

class _Say extends OperationsManager {
  _Say(this.said) {
    operations = [
      operation(
        'say',
        label: 'say',
        run: (run) async {
          said.add('said');
          return 'said';
        },
      ),
    ];
  }

  final List<String> said;

  @override
  String get area => 'launcher://test';

  @override
  late final List<Operation> operations;
}

void main() {
  late List<String> said;
  late ProviderContainer container;

  setUp(() {
    said = [];
    container = ProviderContainer(
      overrides: [
        ...launcherOverrides,
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(
            LauncherConfig(
              entities: const [
                Entity(
                  id: 'desk',
                  category: 'lamp',
                  label: 'Desk',
                  actions: {
                    'wave': EntityAction(run: 'launcher://test/say'),
                    'tidy': EntityAction(
                      run: 'launcher://test/say',
                      access: NodeAccess.protected,
                    ),
                    'hide': EntityAction(
                      run: 'launcher://test/say',
                      access: NodeAccess.private,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(const [], const []),
        ),
        operationsManagersProvider.overrideWith((ref) => [_Say(said)]),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<String?> run(String name, {String? from}) => container
      .read(actionRunnerProvider)
      .run(Act(name, {'entity': 'desk'}), component: from);

  test('a public action can be told to run by anyone', () async {
    expect(await run('wave'), 'said');
    expect(await run('wave', from: 'other'), 'said');
  });

  test('a protected one is for the node and what is under it', () async {
    expect(run('tidy'), throwsA(isA<ImproperAct>()));
    expect(run('tidy', from: 'other'), throwsA(isA<ImproperAct>()));
    expect(await run('tidy', from: 'desk'), 'said');
    expect(await run('tidy', from: 'desk/icon'), 'said');
  });

  test('a private one is for the node alone', () async {
    expect(run('hide', from: 'desk/icon'), throwsA(isA<ImproperAct>()));
    expect(await run('hide', from: 'desk'), 'said');
  });
}
