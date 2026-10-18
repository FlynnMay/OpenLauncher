import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Whether nodes without a layout around them snap to [snapStepProvider]'s
/// grid, which is drawn while it is on. Off by default.
final snapProvider = NotifierProvider<Snap, bool>(Snap.new);

class Snap extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool snap) => state = snap;
}

/// Cell size of the snap grid, in TV pixels.
final snapStepProvider = NotifierProvider<SnapStep, double>(SnapStep.new);

class SnapStep extends Notifier<double> {
  @override
  double build() => freeStep;

  void set(double step) =>
      state = step.clamp(minSnapStep, maxSnapStep).toDouble();
}

/// Default step for snapped placement without a layout, in TV pixels.
const freeStep = 8.0;
const minSnapStep = 1.0, maxSnapStep = 200.0;

/// The placement step in [container]: whole cells, or without a layout TV
/// pixels, [step] apart while [snap] is on.
double stepIn(Node container, {required bool snap, double step = freeStep}) =>
    container.mode == LayoutMode.free && snap ? step : 1;

/// [value] rounded to a multiple of [step], to two decimals.
double snapTo(double value, double step) =>
    ((value / step).roundToDouble() * step * 100).roundToDouble() / 100;

class SnapButton extends ConsumerWidget {
  const SnapButton({super.key});

  static const _presets = [4.0, 8.0, 10.0, 16.0, 20.0, 24.0, 32.0, 48.0, 64.0];

  static String _label(double step) => '${tidy(step)} px';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(snapProvider);
    final step = ref.watch(snapStepProvider);
    return PopupMenuButton<double>(
      tooltip: snap
          ? 'Snap to grid: on, ${_label(step)} cells'
          : 'Snap to grid: off',
      icon: Icon(snap ? Icons.grid_on_outlined : Icons.grid_off_outlined),
      onSelected: (size) {
        // 0 is the toggle row.
        if (size == 0) return ref.read(snapProvider.notifier).set(!snap);
        ref.read(snapStepProvider.notifier).set(size);
        ref.read(snapProvider.notifier).set(true);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 0.0,
          checked: snap,
          child: const Text('Snap to grid'),
        ),
        const PopupMenuDivider(),
        for (final size in {..._presets, step}.toList()..sort())
          PopupMenuItem(
            value: size,
            child: Text(
              _label(size),
              style: size == step
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
        PopupMenuItem(
          onTap: () => _custom(context, ref, step),
          child: const Text('Custom...'),
        ),
      ],
    );
  }

  Future<void> _custom(BuildContext context, WidgetRef ref, double step) async {
    final field = TextEditingController(text: tidy(step).toString());
    final size = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grid cell size (pixels)'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (text) => Navigator.pop(context, double.tryParse(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(field.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    field.dispose();
    if (size == null || !size.isFinite) return;
    ref.read(snapStepProvider.notifier).set(size);
    ref.read(snapProvider.notifier).set(true);
  }
}

/// Lines every [step] pixels over a free container while snapping is on.
class SnapGrid extends StatelessWidget {
  const SnapGrid({super.key, required this.step, required this.child});

  final double step;
  final Widget child;

  /// Closer than this, lines are a blur.
  static const _least = 4.0;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      if (step >= _least)
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _GridPainter(step))),
        ),
    ],
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.step);

  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.step != step;
}

/// Whether the stage draws nodes that are hidden, faded; off, they are left
/// out as the TV leaves them.
final showHiddenProvider = NotifierProvider<ShowHidden, bool>(ShowHidden.new);

class ShowHidden extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool show) => state = show;
}

class ShowHiddenButton extends ConsumerWidget {
  const ShowHiddenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showHiddenProvider);
    return IconButton(
      tooltip: show ? 'Show hidden: on' : 'Show hidden: off',
      icon: Icon(
        show ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      onPressed: () => ref.read(showHiddenProvider.notifier).set(!show),
    );
  }
}
