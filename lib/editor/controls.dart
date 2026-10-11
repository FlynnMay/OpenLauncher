import 'package:flutter/material.dart';

// Small controls used by every settings panel. A null value means "mixed":
// the edited things differ.

/// The value all of [values] share, or null.
T? shared<T>(Iterable<T> values) =>
    values.toSet().length == 1 ? values.first : null;

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
  late bool _open =
      PageStorage.maybeOf(context)?.readState(context, identifier: _memory)
          as bool? ??
      widget.open;

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

class LabelledRow extends StatelessWidget {
  const LabelledRow(this.label, this.child, {super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(child: child),
      ],
    ),
  );
}

/// An integer with a button either side. Null means mixed; below [min] means
/// "default" when [usual] is set.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.usual,
  });

  final String label;
  final double? value;
  final int min, max, step;
  final String? usual;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final lowest = usual == null ? min : min - step;
    final shown = value == null
        ? 'Mixed'
        : value < min
        ? usual!
        : value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(2);
    // From mixed, the first press goes to the minimum.
    final from = value?.round() ?? lowest;
    return LabelledRow(
      label,
      Row(
        children: [
          IconButton(
            tooltip: 'Less',
            visualDensity: VisualDensity.compact,
            onPressed: value != null && value <= lowest
                ? null
                : () => onChanged(
                    value == null ? lowest : (from - step).clamp(lowest, max),
                  ),
            icon: const Icon(Icons.remove),
          ),
          Expanded(child: Text(shown, textAlign: TextAlign.center)),
          IconButton(
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            onPressed: value != null && value >= max
                ? null
                : () => onChanged(
                    value == null
                        ? min
                        : (value < min ? min : from + step).clamp(min, max),
                  ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// A switch that can also show mixed.
class TickBox extends StatelessWidget {
  const TickBox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    tristate: value == null,
    title: Text(label),
    value: value,
    // From mixed, a press turns it on.
    onChanged: (next) => onChanged(next ?? true),
  );
}

class ChoiceBox<T> extends StatelessWidget {
  const ChoiceBox({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final T? value;
  final Map<T, String> choices;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<T>(
    isExpanded: true,
    isDense: true,
    value: value,
    hint: const Text('Mixed'),
    items: [
      for (final MapEntry(:key, value: label) in choices.entries)
        DropdownMenuItem(value: key, child: Text(label)),
    ],
    onChanged: (next) {
      if (next != null && next != value) onChanged(next);
    },
  );
}

class SlideBar extends StatefulWidget {
  const SlideBar({
    super.key,
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value, max;
  final int divisions;

  /// The label shown while dragging.
  final String Function(double value) label;
  final void Function(double value) onChanged;

  @override
  State<SlideBar> createState() => _SlideBarState();
}

class _SlideBarState extends State<SlideBar> {
  /// The value while dragging; committed on release.
  double? _held;

  @override
  Widget build(BuildContext context) => Slider(
    value: (_held ?? widget.value).clamp(0, widget.max),
    max: widget.max,
    divisions: widget.divisions,
    label: widget.label(_held ?? widget.value),
    onChanged: (value) => setState(() => _held = value),
    onChangeEnd: (value) {
      setState(() => _held = null);
      widget.onChanged(value);
    },
  );
}

/// A text field committed on Enter or blur.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label, value;
  final void Function(String value) onChanged;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final _text = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _take();
    });

  void _take() {
    final value = _text.text.trim();
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    // Updated from outside while not focused.
    if (widget.value != old.value && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _take(),
    ),
  );
}

/// For settings that make a request: [busy] while pending, errors shown in a
/// snackbar.
mixin Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> whileBusy(Future<void> Function() work) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await work();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$error'.replaceFirst(RegExp(r'^Exception: '), '')),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// A confirmation dialog; [does] is the confirm button's label.
Future<bool> sureToRemove(
  BuildContext context,
  String title,
  String does,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'What is in it comes off the TV with it. The apps can be added '
          'again anywhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(does),
          ),
        ],
      ),
    ) ??
    false;
