import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/services/command_service.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';
import 'package:openlauncher/editor/editing/selection.dart';
import 'package:openlauncher_domain/commands/commands.dart';

/// What undo puts back in the editor: the selection and the open prefabs. The
/// change itself is undone by the TV.
typedef Moment = ({Set<String> selection, List<PrefabMode> trail});

typedef Moments = ({List<Moment> past, List<Moment> future});

/// One moment for each change the TV can undo or redo for this editor, newest
/// last.
final historyProvider = NotifierProvider<History, Moments>(History.new);

class History extends Notifier<Moments> {
  static const limit = 100;

  @override
  Moments build() => (past: const [], future: const []);

  Moment _currentViewMoment() => (
    selection: ref.read(selectionProvider),
    trail: ref.read(prefabTrailProvider),
  );

  /// The TV did a change: keep how the editor looked, to undo to.
  void recordChange() {
    final past = [...state.past, _currentViewMoment()];
    state = (
      past: past.sublist(past.length > limit ? past.length - limit : 0),
      future: const [],
    );
  }

  Future<void> undo() => _undoOrRedo(back: true);

  Future<void> redo() => _undoOrRedo(back: false);

  Future<void> _undoOrRedo({required bool back}) async {
    final from = back ? state.past : state.future;
    if (from.isEmpty) return;
    final commands = ref.read(commandsProvider);
    try {
      await (back ? commands.undo() : commands.redo());
    } on CommandRefused {
      // The TV has nothing to undo for this editor: it was restarted, or the
      // steps here are no longer its steps.
      state = (past: const [], future: const []);
      rethrow;
    }
    final to = from.last, rest = from.sublist(0, from.length - 1);
    final now = _currentViewMoment();
    state = back
        ? (past: rest, future: [...state.future, now])
        : (past: [...state.past, now], future: rest);
    ref.read(prefabTrailProvider.notifier).restore(to.trail);
    ref.read(selectionProvider.notifier).restore(to.selection);
  }
}
