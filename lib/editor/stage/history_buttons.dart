import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// Undo and redo.
class HistoryButtons extends ConsumerWidget {
  const HistoryButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Undo (Ctrl+Z)',
          onPressed: history.past.isEmpty
              ? null
              : () => stepHistory(context, ref, back: true),
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo (Ctrl+Shift+Z)',
          onPressed: history.future.isEmpty
              ? null
              : () => stepHistory(context, ref, back: false),
          icon: const Icon(Icons.redo),
        ),
      ],
    );
  }
}
