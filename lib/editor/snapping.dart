import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Whether components in a free pane still snap to whole cells. On by
/// default.
final snapProvider = NotifierProvider<Snap, bool>(Snap.new);

class Snap extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool snap) => state = snap;
}

/// Step for unsnapped placement, in cells.
const freeStep = 0.05;

/// The placement step in [pane]: whole cells, or [freeStep] in a free pane
/// with [snap] off.
double stepIn(Component pane, {required bool snap}) =>
    pane.mode == PaneMode.free && !snap ? freeStep : 1;

/// [value] rounded to a multiple of [step], to two decimals.
double snapTo(double value, double step) =>
    ((value / step).roundToDouble() * step * 100).roundToDouble() / 100;

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
