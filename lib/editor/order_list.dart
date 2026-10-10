import 'package:flutter/material.dart';

/// A list of things of which some are chosen, in an order of the user's:
/// each can be ticked, and the ticked ones dragged into place. Those not
/// chosen stay listed after the chosen ones.
class OrderList<T> extends StatelessWidget {
  const OrderList({
    super.key,
    required this.all,
    required this.chosen,
    required this.label,
    required this.onChanged,
  });

  /// Everything there is to choose from.
  final List<T> all;

  /// What is chosen, in order.
  final List<T> chosen;
  final String Function(T value) label;
  final void Function(List<T> chosen) onChanged;

  @override
  Widget build(BuildContext context) {
    final rest = [
      for (final value in all)
        if (!chosen.contains(value)) value,
    ];
    final rows = [...chosen, ...rest];
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) {
        // Only the chosen have a place; it is kept among them.
        if (from >= chosen.length) return;
        final next = [...chosen];
        final moved = next.removeAt(from);
        next.insert(to.clamp(0, next.length), moved);
        onChanged(next);
      },
      children: [
        for (final (index, value) in rows.indexed)
          Row(
            key: ValueKey(value),
            children: [
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: chosen.contains(value),
                onChanged: (on) => onChanged(
                  on ?? false
                      ? [...chosen, value]
                      : [
                          for (final other in chosen)
                            if (other != value) other,
                        ],
                ),
              ),
              Expanded(child: Text(label(value))),
              if (index < chosen.length)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle, size: 20),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
