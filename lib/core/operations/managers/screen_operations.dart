import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/screens/screens.dart';

/// Which screen is shown, and the screens there are.
class ScreenOperationsManager implements OperationsManager {
  ScreenOperationsManager(this._ref);

  final Ref _ref;

  /// The screen the argument `id` names; empty, the one shown. Null if there
  /// is none.
  Future<Screen?> _named(OperationRun run) async {
    final layout = (await _ref.read(configProvider.future)).layout;
    final id = run.arg('id');
    return id == null ? _ref.read(currentScreenProvider) : layout.screen(id);
  }

  Future<void> _edit(Layout Function(Layout layout) change) async {
    final config = await _ref.read(configProvider.future);
    await _ref.read(configProvider.notifier).setLayout(change(config.layout));
  }

  /// [pictures] with the entries of the nodes in [renamed] repeated for
  /// their new ids.
  static Map<String, String> _copied(
    Map<String, String> pictures,
    Map<String, String> renamed,
  ) => {
    ...pictures,
    for (final MapEntry(:key, :value) in renamed.entries)
      Layout.pictureKey(value): ?pictures[Layout.pictureKey(key)],
  };

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'launcher://screen/open',
      label: 'Show a screen',
      args: const {'id': []},
      run: (run) async {
        final id = run.arg('id');
        if (id == null) return null;
        final layout = (await _ref.read(configProvider.future)).layout;
        if (layout.screen(id) == null) return 'There is no screen "$id".';
        _ref.read(shownScreensProvider.notifier).open(id);
        return null;
      },
    ),
    Operation(
      name: 'launcher://screen/add',
      label: 'Add an empty screen',
      // `id` is wanted, not promised; `name` is its label.
      args: const {'id': [], 'name': []},
      run: (run) async {
        final layout = (await _ref.read(configProvider.future)).layout;
        final name = run.arg('name') ?? '';
        final id = freeId(
          run.arg('id') ?? slugOf(name, 'screen'),
          layout.itemIds,
        );
        final empty = Screen.empty(id);
        await _edit(
          (layout) => layout.copyWith(
            screens: [
              ...layout.screens,
              empty.withRoot(empty.root.copyWith(name: name)),
            ],
          ),
        );
        return 'Screen "$id" was added.';
      },
    ),
    Operation(
      name: 'launcher://screen/remove',
      label: 'Remove a screen',
      args: const {'id': []},
      run: (run) async {
        final screen = await _named(run);
        if (screen == null) return 'There is no such screen.';
        final layout = (await _ref.read(configProvider.future)).layout;
        if (layout.screens.length < 2) return 'The last screen stays.';
        await _edit(
          (layout) => layout.copyWith(
            screens: [
              for (final one in layout.screens)
                if (one.id != screen.id) one,
            ],
          ),
        );
        return 'Screen "${screen.id}" was removed.';
      },
    ),
    Operation(
      name: 'launcher://screen/rename',
      label: 'Rename a screen',
      args: const {'id': [], 'name': []},
      run: (run) async {
        final screen = await _named(run);
        if (screen == null) return 'There is no such screen.';
        final name = run.arg('name') ?? '';
        await _edit(
          (layout) => layout.copyWith(
            screens: [
              for (final one in layout.screens)
                one.id == screen.id
                    ? one.withRoot(one.root.copyWith(name: name))
                    : one,
            ],
          ),
        );
        return null;
      },
    ),
    Operation(
      name: 'launcher://screen/duplicate',
      label: 'Copy a screen',
      args: const {'id': []},
      run: (run) async {
        final original = await _named(run);
        if (original == null) return 'There is no such screen.';
        final layout = (await _ref.read(configProvider.future)).layout;
        final id = freeId(original.id, layout.itemIds);
        final (:screen, :renamed) = original.copied(id);
        await _ref
            .read(configProvider.notifier)
            .change(
              (c) => c.copyWith(
                // Pictures set on a node go with its copy.
                iconOverrides: _copied(c.iconOverrides, renamed),
                iconSources: _copied(c.iconSources, renamed),
                layout: c.layout.copyWith(
                  screens: [
                    for (final one in c.layout.screens) ...[
                      one,
                      if (one.id == original.id) screen,
                    ],
                  ],
                ),
              ),
            );
        return 'Screen "$id" was added.';
      },
    ),
    Operation(
      name: 'launcher://screen/startup',
      label: 'Set which screen the launcher opens on',
      // `id` is the screen to start on, empty to keep it; `remember` opens on
      // the screen shown last instead.
      args: const {
        'id': [],
        'remember': ['true', 'false'],
      },
      run: (run) async {
        final layout = (await _ref.read(configProvider.future)).layout;
        final id = run.arg('id');
        if (id != null && layout.screen(id) == null) {
          return 'There is no screen "$id".';
        }
        await _edit(
          (layout) => layout.copyWith(
            startup: Startup(
              id ?? layout.startup.screen,
              remember: run.flag(
                'remember',
                otherwise: layout.startup.remember,
              ),
            ),
          ),
        );
        return null;
      },
    ),
  ];
}
