import 'package:flutter/material.dart';

// The small parts every panel of settings is made of. Each shows one value
// and reports a change; none knows what the value belongs to. A value of
// null means "mixed": the things being edited differ.

/// The one value all of [values] share, or null when they differ.
T? shared<T>(Iterable<T> values) =>
    values.toSet().length == 1 ? values.first : null;

/// A group of like settings under a heading, which a press closes and opens
/// again. Whether it is open is remembered by its [title] for as long as
/// the page is up, so it stays as it was left from one thing picked out to
/// the next.
class Section extends StatefulWidget {
  const Section(this.title, this.children, {super.key, this.open = true});

  final String title;
  final List<Widget> children;

  /// Whether it is open until it has been pressed.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Tooltip(
                  message: _open ? 'Close' : 'Open',
                  child: Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
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
}

/// A setting with its name in front of it.
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

/// A whole number with a button either side. No [value] means the selected
/// things differ; a value below [min] stands for "the usual", when [usual]
/// names that.
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
    // From "differs", the first press settles on the lowest.
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

/// A switch that is neither on nor off while the selected things differ.
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
    // From "differs", a press turns it on for all of them.
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

  /// How a value reads, shown over the thumb while it is held.
  final String Function(double value) label;
  final void Function(double value) onChanged;

  @override
  State<SlideBar> createState() => _SlideBarState();
}

class _SlideBarState extends State<SlideBar> {
  /// Where the thumb is while it is held; the change is made on letting go.
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

/// A line of text that is taken when Enter is pressed or it is left.
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
    // Changed from elsewhere, and not being typed in here.
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

/// For a setting that sends something off and waits: [busy] while it is on
/// its way, and what went wrong said at the foot of the page.
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

/// Asks before something is taken away with what is in it: [title] is the
/// question and [does] what the button that goes ahead says.
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
