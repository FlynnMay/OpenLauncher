import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Whether nodes without a layout around them snap to [freeStep]. On by
/// default.
final snapProvider = NotifierProvider<Snap, bool>(Snap.new);

class Snap extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool snap) => state = snap;
}

/// Step for snapped placement without a layout, in TV pixels.
const freeStep = 8.0;

/// The placement step in [container]: whole cells, or without a layout TV
/// pixels, [freeStep] apart while [snap] is on.
double stepIn(Node container, {required bool snap}) =>
    container.mode == LayoutMode.free && snap ? freeStep : 1;

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
          ? 'Snap to grid: on. Press to place and size freely where there '
                'is no layout.'
          : 'Snap to grid: off. Press to keep things to an 8 pixel grid.',
      isSelected: snap,
      onPressed: () => ref.read(snapProvider.notifier).set(!snap),
      icon: const Icon(Icons.grid_off_outlined),
      selectedIcon: const Icon(Icons.grid_on_outlined),
    );
  }
}
