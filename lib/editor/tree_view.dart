import 'package:flutter/material.dart';

/// One line of a [TreeView]: something that can be ticked or picked,
/// [value], or a heading over the [children] it can be opened to show, or
/// both.
@immutable
class TreeNode<T> {
  const TreeNode({
    required this.label,
    this.value,
    this.children = const [],
    this.leading,
    this.trailing,
    this.id,
  });

  final String label;

  /// What ticking this line switches; null for a line that is only a
  /// heading, which is ticked when everything under it is.
  final T? value;
  final List<TreeNode<T>> children;

  /// Shown in front of the label, and at the end of the line.
  final Widget? leading, trailing;

  /// What tells this line from the others when the lines are made anew
  /// each time they are shown, so that a heading stays open or closed.
  /// Without one, the line itself has to stay the same.
  final Object? id;

  /// The values of this line and of every line under it.
  Iterable<T> get values sync* {
    if (value case final value?) yield value;
    for (final child in children) {
      yield* child.values;
    }
  }
}

/// A list of things to tick, some of them under headings that open and
/// close. Ticking a heading ticks everything under it; a heading with only
/// some of what is under it ticked shows as neither.
///
/// [TreeView.pick] is the same list with nothing to tick: a press on a
/// line picks that line alone, and the lines that are picked are marked.
class TreeView<T> extends StatefulWidget {
  const TreeView({
    super.key,
    required this.nodes,
    required this.checked,
    required void Function(Set<T> values, bool checked) this.onChanged,
    this.startOpen = true,
  }) : onPicked = null;

  const TreeView.pick({
    super.key,
    required this.nodes,
    required Set<T> picked,
    required void Function(T value) this.onPicked,
    this.startOpen = true,
  }) : checked = picked,
       onChanged = null;

  final List<TreeNode<T>> nodes;

  /// The values that are ticked, or picked.
  final Set<T> checked;

  /// Called with the values a tick was put on or taken off.
  final void Function(Set<T> values, bool checked)? onChanged;

  /// Called with the value of a line that was pressed, where lines are
  /// picked rather than ticked.
  final void Function(T value)? onPicked;

  /// Whether headings start out open.
  final bool startOpen;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  /// The headings whose state is the other one than they started in.
  final _toggled = <Object>{};

  static const _indent = 20.0;

  bool _open(TreeNode<T> node) =>
      widget.startOpen != _toggled.contains(node.id ?? node);

  void _toggle(TreeNode<T> node) => setState(() {
    final key = node.id ?? node;
    _toggled.remove(key) || _toggled.add(key);
  });

  Iterable<Widget> _lines(TreeNode<T> node, int depth) sync* {
    final values = node.values.toSet();
    final all = values.isNotEmpty && widget.checked.containsAll(values);
    final some = values.any(widget.checked.contains);
    final parent = node.children.isNotEmpty;
    final onPicked = widget.onPicked;
    final picked =
        onPicked != null &&
        node.value != null &&
        widget.checked.contains(node.value);
    yield InkWell(
      onTap: onPicked != null
          // A heading that is nothing by itself just opens and closes.
          ? switch (node.value) {
              final value? => () => onPicked(value),
              null => parent ? () => _toggle(node) : null,
            }
          // From some to all, from all to none.
          : values.isEmpty
          ? null
          : () => widget.onChanged!(values, !all),
      child: Ink(
        color: picked ? Theme.of(context).colorScheme.secondaryContainer : null,
        padding: EdgeInsets.only(left: 4 + depth * _indent, right: 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: parent
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      tooltip: _open(node) ? 'Close' : 'Open',
                      onPressed: () => _toggle(node),
                      icon: Icon(
                        _open(node) ? Icons.expand_more : Icons.chevron_right,
                      ),
                    )
                  : null,
            ),
            if (onPicked == null)
              // The line is what is pressed; the box only shows.
              IgnorePointer(
                child: Checkbox(
                  tristate: true,
                  visualDensity: VisualDensity.compact,
                  value: all
                      ? true
                      : some
                      ? null
                      : false,
                  onChanged: values.isEmpty ? null : (_) {},
                ),
              ),
            if (node.leading case final leading?) ...[
              leading,
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: parent
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
              ),
            ),
            ?node.trailing,
          ],
        ),
      ),
    );
    if (parent && _open(node)) {
      for (final child in node.children) {
        yield* _lines(child, depth + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final node in widget.nodes) ..._lines(node, 0)],
  );
}
