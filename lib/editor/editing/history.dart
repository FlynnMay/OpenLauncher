import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';
import 'package:openlauncher/editor/editing/selection.dart';

/// What undo puts back: the config, the selection and the open prefabs.
typedef Moment = ({
  LauncherConfig config,
  Set<String> selection,
  List<PrefabMode> trail,
});

typedef Moments = ({List<Moment> past, List<Moment> future});

/// The editor's undo and redo steps, newest last.
final historyProvider = NotifierProvider<History, Moments>(History.new);

class History extends Notifier<Moments> {
  static const limit = 100;

  /// While a step is being put back, which is not itself a change.
  bool _restoring = false;

  @override
  Moments build() => (past: const [], future: const []);

  Moment _moment(LauncherConfig config) => (
    config: config,
    selection: ref.read(selectionProvider),
    trail: ref.read(prefabTrailProvider),
  );

  /// Keeps [before], the config a change is replacing, as a step to undo to.
  void record(LauncherConfig before) {
    if (_restoring) return;
    final past = [...state.past, _moment(before)];
    state = (
      past: past.sublist(past.length > limit ? past.length - limit : 0),
      future: const [],
    );
  }

  Future<void> undo() => _step(back: true);

  Future<void> redo() => _step(back: false);

  Future<void> _step({required bool back}) async {
    final from = back ? state.past : state.future;
    final config = ref.read(configProvider).value;
    if (from.isEmpty || config == null || _restoring) return;
    final to = from.last, rest = from.sublist(0, from.length - 1);
    final now = _moment(config);
    state = back
        ? (past: rest, future: [...state.future, now])
        : (past: [...state.past, now], future: rest);
    _restoring = true;
    try {
      ref.read(prefabTrailProvider.notifier).restore(to.trail);
      ref.read(selectionProvider.notifier).restore(to.selection);
      await ref.read(configProvider.notifier).change((_) => to.config);
    } on Object {
      // What the TV has is unknown now: start again from it.
      state = (past: const [], future: const []);
      ref.invalidate(configProvider);
      rethrow;
    } finally {
      _restoring = false;
    }
  }
}
