import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/layout_edit.dart';

/// The ids of the items picked out for editing.
final selectionProvider = NotifierProvider<Selection, Set<String>>(
  Selection.new,
);

class Selection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// A tap on the item [id]: it becomes the selection, or with [adding]
  /// joins or leaves it.
  void tap(String id, {required bool adding}) {
    if (!adding) {
      state = {id};
    } else if (state.contains(id)) {
      state = {...state}..remove(id);
    } else {
      state = {...state, id};
    }
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

/// Whether a tap adds to the selection without a key held down: the way to
/// pick several things by finger.
final selectSeveralProvider = NotifierProvider<SelectSeveral, bool>(
  SelectSeveral.new,
);

class SelectSeveral extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool several) => state = several;
}

/// The selected items as they are in the layout now. What has since been
/// removed is simply not among them.
final selectedProvider = Provider<List<Found>>((ref) {
  final layout = ref.watch(configProvider).value?.layout;
  final ids = ref.watch(selectionProvider);
  return layout == null || ids.isEmpty ? const [] : findItems(layout, ids);
});

/// The sidebar being arranged, by panel id: held open on the screen, with
/// its settings in the panel while nothing in it is picked out.
final barProvider = NotifierProvider<EditedBar, String?>(EditedBar.new);

class EditedBar extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

/// The popups the selected folder cards open, by panel id.
final selectedPanelsProvider = Provider<Map<String, Panel>>((ref) {
  final layout = ref.watch(configProvider).value?.layout;
  final panels = <String, Panel>{};
  for (final one in ref.watch(selectedProvider)) {
    if (one.item.kind != ItemKind.panel) continue;
    if (layout?.panel(one.item.ref) case final panel?) panels[panel.id] = panel;
  }
  return panels;
});

/// The pane new apps go to.
final inboxProvider = Provider<String?>(
  (ref) => ref.watch(configProvider).value?.layout.inbox,
);
