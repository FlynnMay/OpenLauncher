import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/editing/layout_edit.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';

/// Ids of the selected components.
final selectionProvider = NotifierProvider<Selection, Set<String>>(
  Selection.new,
);

class Selection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Selects [id], or toggles it when [adding].
  void tap(String id, {required bool adding}) {
    if (!adding) {
      state = {id};
    } else if (state.contains(id)) {
      state = {...state}..remove(id);
    } else {
      state = {...state, id};
    }
  }

  /// A click on [id]: toggles it in multi-select mode or with Ctrl/Shift/Cmd
  /// held, otherwise selects only it.
  void press(String id) {
    final keys = HardwareKeyboard.instance;
    tap(
      id,
      adding:
          ref.read(selectSeveralProvider) ||
          keys.isControlPressed ||
          keys.isShiftPressed ||
          keys.isMetaPressed,
    );
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }

  void restore(Set<String> ids) => state = ids;
}

/// Multi-select without a modifier key, for touch.
final selectSeveralProvider = NotifierProvider<SelectSeveral, bool>(
  SelectSeveral.new,
);

class SelectSeveral extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool several) => state = several;
}

/// The selected components as they are now, in what is being edited.
final selectedProvider = Provider<List<Found>>((ref) {
  final layout = ref.watch(editedLayoutProvider);
  final ids = ref.watch(selectionProvider);
  return layout == null || ids.isEmpty ? const [] : findItems(layout, ids);
});

/// Briefly lets go of the selected docked container to preview its opening.
final barReplayProvider = NotifierProvider<BarReplay, bool>(BarReplay.new);

class BarReplay extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> play() async {
    if (state) return;
    state = true;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (ref.mounted) state = false;
  }
}

/// The nodes the selected instances are handed, rather than entities, by
/// id.
final selectedHandedProvider = Provider<Map<String, Node>>((ref) {
  final layout = ref.watch(configProvider).value?.layout;
  return {
    for (final one in ref.watch(selectedProvider))
      if (one.item.isInstance)
        for (final id in one.item.handed)
          if (layout?.node(id) != null) id: layout!.node(id)!,
  };
});

final inboxProvider = Provider<String?>(
  (ref) => ref.watch(configProvider).value?.layout.inbox,
);
