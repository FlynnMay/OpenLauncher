import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Whether things in a pane that lets them be anywhere still land on whole
/// cells. On unless switched off: freedom is there for the asking.
final snapProvider = NotifierProvider<Snap, bool>(Snap.new);

class Snap extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool snap) => state = snap;
}

/// How finely something can be placed and sized off the cells.
const freeStep = 0.05;

/// The steps, in cells, that a place or a size in [pane] goes by: whole
/// cells, or with [snap] off in a pane that lets things be anywhere, small
/// fractions of one.
double stepIn(Pane pane, {required bool snap}) =>
    pane.mode == PaneMode.free && !snap ? freeStep : 1;

/// [value] at the nearest multiple of [step], to the hundredth the layout
/// keeps.
double snapTo(double value, double step) =>
    ((value / step).roundToDouble() * step * 100).roundToDouble() / 100;

/// Switches snapping to whole cells on and off.
class SnapButton extends ConsumerWidget {
  const SnapButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(snapProvider);
    return IconButton(
      tooltip: snap
          ? 'Things land on whole cells. Press to place and size them '
                'freely in "Anywhere" panes.'
          : 'In "Anywhere" panes things go exactly where they are put. '
                'Press to keep them to whole cells.',
      isSelected: snap,
      onPressed: () => ref.read(snapProvider.notifier).set(!snap),
      icon: const Icon(Icons.grid_off_outlined),
      selectedIcon: const Icon(Icons.grid_on_outlined),
    );
  }
}
