import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/prefab_edit.dart';

/// A prefab opened for editing in place of the layout: the variant shown,
/// the height in TV pixels it is drawn at where that is not its own (a card
/// in a sidebar's row), what its empty variables are drawn with, and the
/// instance it was opened from.
typedef PrefabMode = ({
  String id,
  String? variant,
  double? height,
  Map<String, String> previews,
  String? via,
});

/// The prefabs opened one from inside another, outermost first; the last is
/// the one being edited.
final prefabTrailProvider = NotifierProvider<PrefabTrail, List<PrefabMode>>(
  PrefabTrail.new,
);

class PrefabTrail extends Notifier<List<PrefabMode>> {
  @override
  List<PrefabMode> build() => const [];

  /// Opens [id]: inside the one that is open when [nested], else alone.
  void open(
    String id, {
    Map<String, String> previews = const {},
    String? via,
    bool nested = false,
  }) => state = [
    if (nested) ...state,
    (id: id, variant: null, height: null, previews: previews, via: via),
  ];

  void _change(PrefabMode Function(PrefabMode mode) how) {
    if (state.isEmpty) return;
    state = [...state.take(state.length - 1), how(state.last)];
  }

  void show(String? variant) => _change(
    (mode) => (
      id: mode.id,
      variant: variant,
      height: mode.height,
      previews: mode.previews,
      via: mode.via,
    ),
  );

  void drawAt(double? height) => _change(
    (mode) => (
      id: mode.id,
      variant: mode.variant,
      height: height,
      previews: mode.previews,
      via: mode.via,
    ),
  );

  void preview(String name, String with_) => _change(
    (mode) => (
      id: mode.id,
      variant: mode.variant,
      height: mode.height,
      previews: {...mode.previews, name: with_},
      via: mode.via,
    ),
  );

  /// Keeps the first [length] of the trail; 0 is back to the layout.
  void backTo(int length) => state = state.take(length).toList();
}

/// The prefab opened last, if any.
final prefabModeProvider = Provider<PrefabMode?>(
  (ref) => ref.watch(prefabTrailProvider).lastOrNull,
);

/// The prefab being edited, if any.
final editedPrefabProvider = Provider<Prefab?>((ref) {
  final mode = ref.watch(prefabModeProvider);
  return mode == null ? null : ref.watch(prefabsProvider)[mode.id];
});

/// What the editing tools work on: the layout, or the edited prefab as one.
final editedLayoutProvider = Provider<Layout?>((ref) {
  final layout = ref.watch(
    configProvider.select((config) => config.value?.layout),
  );
  final prefab = ref.watch(editedPrefabProvider);
  final mode = ref.watch(prefabModeProvider);
  return prefab == null || layout == null
      ? layout
      : prefabAsLayout(prefab, mode?.variant, mode?.height);
});
