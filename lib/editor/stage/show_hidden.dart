import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
