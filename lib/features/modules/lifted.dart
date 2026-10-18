import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Links each lifted node's spot to it drawn over the screen, by id.
final _linksProvider = Provider((ref) => <String, LayerLink>{});

/// The size of each lifted node's spot, by id.
final _sizesProvider = NotifierProvider<_Sizes, Map<String, Size>>(_Sizes.new);

class _Sizes extends Notifier<Map<String, Size>> {
  @override
  Map<String, Size> build() => const {};

  void set(String id, Size size) {
    if (state[id] != size) state = {...state, id: size};
  }
}

/// Where node [id] sits while it is drawn over the screen: [child] keeps
/// its room, unseen and out of the focus.
class LiftedSpot extends ConsumerStatefulWidget {
  const LiftedSpot({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<LiftedSpot> createState() => _LiftedSpotState();
}

class _LiftedSpotState extends ConsumerState<LiftedSpot> {
  void _measure(_) {
    if (!mounted) return;
    if (context.findRenderObject() case final RenderBox box when box.hasSize) {
      ref.read(_sizesProvider.notifier).set(widget.id, box.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    return CompositedTransformTarget(
      link: ref.watch(_linksProvider).putIfAbsent(widget.id, LayerLink.new),
      child: Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: widget.child,
      ),
    );
  }
}

/// [child], node [id] drawn over the screen where its [LiftedSpot] is. Goes
/// in a [Stack].
class Lifted extends ConsumerWidget {
  const Lifted({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(_sizesProvider.select((all) => all[id]));
    if (size == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: ref.watch(_linksProvider).putIfAbsent(id, LayerLink.new),
        showWhenUnlinked: false,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}
