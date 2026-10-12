import 'package:flutter/material.dart';

/// A collapsible group of settings. Its open state is remembered by [title]
/// for the life of the page.
class Section extends StatefulWidget {
  const Section(this.title, this.children, {super.key, this.open = true});

  final String title;
  final List<Widget> children;

  /// Initial state.
  final bool open;

  @override
  State<Section> createState() => _SectionState();
}

class _SectionState extends State<Section> {
  late bool _open = _remembered;

  bool get _remembered =>
      PageStorage.maybeOf(context)?.readState(context, identifier: _memory)
          as bool? ??
      widget.open;

  @override
  void didUpdateWidget(Section old) {
    super.didUpdateWidget(old);
    // Reused for another section when one appears above it.
    if (old.title != widget.title) _open = _remembered;
  }

  ValueKey<String> get _memory => ValueKey('section ${widget.title}');

  void _toggle() {
    setState(() => _open = !_open);
    PageStorage.maybeOf(context)
        ?.writeState(context, _open, identifier: _memory);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(widget.title, open: _open, onTap: _toggle),
      if (_open)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
    ],
  );
}

/// The row heading a collapsible group. Without [onTap] it cannot be closed.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, required this.open, this.onTap});

  final String title;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (onTap != null)
                  Tooltip(
                    message: open ? 'Close' : 'Open',
                    child: Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
