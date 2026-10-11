import 'package:flutter/material.dart';

/// A row of a [TreeView]: a checkable or pickable [value], a heading over
/// [children], or both.
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

  /// Null for a pure heading, which is checked when all its children are.
  final T? value;
  final List<TreeNode<T>> children;

  final Widget? leading, trailing;

  /// A stable identity, so a heading keeps its open state when nodes are
  /// rebuilt.
  final Object? id;

  /// This row's value and all below it.
  Iterable<T> get values sync* {
    if (value case final value?) yield value;
    for (final child in children) {
      yield* child.values;
    }
  }
}

/// A checkbox tree with collapsible headings; a heading toggles everything
/// under it. [TreeView.pick] is the same without checkboxes: a click picks a
/// row.
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

  final Set<T> checked;

  final void Function(Set<T> values, bool checked)? onChanged;

  final void Function(T value)? onPicked;

  final bool startOpen;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  /// Headings toggled from their initial state.
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
          // A pure heading only expands and collapses.
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
              // The row handles the click.
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
