import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/stage.dart';

/// The one value all of [values] share, or null when they differ.
T? _shared<T>(Iterable<T> values) =>
    values.toSet().length == 1 ? values.first : null;

BoxStyle _styleOf(LayoutItem item) => item.pane?.style ?? item.style;

/// A pane's look is its own; anything else's is the item's.
LayoutItem _withStyle(LayoutItem item, BoxStyle style) => switch (item.pane) {
  null => item.copyWith(style: style),
  final pane => item.withPane(pane.copyWith(style: style)),
};

/// The settings of whatever is picked out on the screen. With several
/// things picked out, only what every one of them has is offered, and a
/// change is made to them all.
class Inspector extends ConsumerWidget {
  const Inspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final found = ref.watch(selectedProvider);
    final several = ref.watch(selectSeveralProvider);
    final cards = {
      for (final card in ref.watch(allCardsProvider).value ?? const [])
        card.id: card,
    };

    final ids = {for (final one in found) one.item.id};
    final items = [for (final one in found) one.item];
    void change(Layout Function(Layout layout) how) =>
        changeLayout(context, ref, how);
    void each(LayoutItem Function(LayoutItem item) how) =>
        change((layout) => changeItems(layout, ids, (item, _) => how(item)));
    void panes(Pane Function(Pane pane) how) =>
        each((item) => item.withPane(how(item.pane!)));

    String name(Found one) {
      final item = one.item;
      return switch (item.kind) {
        ItemKind.card => cards[item.ref]?.label ?? 'Card',
        ItemKind.widget => WidgetKind.named(item.ref)?.label ?? 'Widget',
        ItemKind.pane => item.pane!.title.isEmpty ? 'Pane' : item.pane!.title,
        ItemKind.panel => switch (ref
            .watch(selectedPanelsProvider)[item.ref]
            ?.title) {
          null || '' => 'Folder',
          final title => title,
        },
      };
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (found.length) {
                0 => 'Nothing selected',
                1 => name(found.single),
                final count => '$count selected',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (found.isNotEmpty)
            IconButton(
              tooltip: 'Let go of the selection',
              onPressed: ref.read(selectionProvider.notifier).clear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
    final picking = SwitchListTile(
      dense: true,
      title: const Text('Select several'),
      subtitle: const Text('Or hold Ctrl or Shift while clicking'),
      value: several,
      onChanged: ref.read(selectSeveralProvider.notifier).set,
    );
    if (found.isEmpty) {
      return ListView(
        children: [
          header,
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Tap something on the screen to change its size, colours '
              'and other settings.',
            ),
          ),
          picking,
        ],
      );
    }

    // What every one of the selected things is decides what is offered.
    final allPanes = items.every((item) => item.kind == ItemKind.pane);
    final allNamed = items.every(
      (item) => item.kind == ItemKind.card || item.kind == ItemKind.panel,
    );
    final allFolders = items.every((item) => item.kind == ItemKind.panel);
    final folders = ref.watch(selectedPanelsProvider);
    final style = _styleOf(items.first);
    // Each part of the look is changed by itself, so that giving several
    // things the same border leaves each its own background.
    bool same(Object? Function(BoxStyle style) part) =>
        items.map((item) => jsonEncode(part(_styleOf(item)))).toSet().length ==
        1;
    final sameFill = same((style) => style.colors);
    final sameBorder = same((style) => style.border);
    void restyle(BoxStyle Function(BoxStyle own) how) =>
        each((item) => _withStyle(item, how(_styleOf(item))));
    void fill(List<int> colors) => restyle(
      (own) => BoxStyle(colors: colors, angle: own.angle, border: own.border),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        header,
        picking,
        _Section('Size', [
          _Stepper(
            label: 'Cells wide',
            value: _shared(items.map((item) => item.w)),
            min: 1,
            max: found
                .map((one) => one.parent.columns)
                .reduce((a, b) => a < b ? a : b),
            onChanged: (w) =>
                change((layout) => resizeItems(layout, ids, w: w * 1.0)),
          ),
          _Stepper(
            label: 'Cells tall',
            value: _shared(items.map((item) => item.h)),
            min: 1,
            max: Pane.maxRows,
            onChanged: (h) =>
                change((layout) => resizeItems(layout, ids, h: h * 1.0)),
          ),
        ]),
        if (allNamed)
          _Section('Name', [
            _Tick(
              label: 'Show the name',
              value: _shared(items.map((item) => !item.hideName)),
              onChanged: (shown) =>
                  each((item) => item.copyWith(hideName: !shown)),
            ),
          ]),
        _Section('Colours', [
          _Row(
            sameFill ? 'Background' : 'Background\n(mixed)',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, colour) in style.colors.indexed)
                  ColourChip(
                    colour: colour,
                    onChanged: (next) => fill(
                      [...style.colors]
                        ..replaceRange(index, index + 1, [?next]),
                    ),
                  ),
                if (style.colors.length < BoxStyle.maxColors)
                  ColourChip(
                    colour: null,
                    tooltip: style.colors.isEmpty
                        ? 'Give it a background colour'
                        : 'Add a colour, for a gradient',
                    onChanged: (next) => fill([...style.colors, ?next]),
                  ),
              ],
            ),
          ),
          if (style.colors.length > 1)
            _Row(
              'Direction',
              _Slide(
                value: style.angle * 1.0,
                max: 345,
                divisions: 23,
                label: '${style.angle}°',
                onChanged: (angle) => restyle(
                  (own) => BoxStyle(
                    colors: own.colors,
                    angle: angle.round(),
                    border: own.border,
                  ),
                ),
              ),
            ),
          _Row(
            sameBorder ? 'Border' : 'Border\n(mixed)',
            Align(
              alignment: Alignment.centerLeft,
              child: ColourChip(
                colour: style.border,
                tooltip: 'Give it a border',
                onChanged: (next) => restyle(
                  (own) => BoxStyle(
                    colors: own.colors,
                    angle: own.angle,
                    border: next,
                  ),
                ),
              ),
            ),
          ),
        ]),
        if (allPanes) ...[
          _Section('Pane', [
            if (found.length == 1)
              _Field(
                label: 'Title',
                value: items.single.pane!.title,
                onChanged: (title) =>
                    panes((pane) => pane.copyWith(title: title)),
              ),
            _Row(
              'Placement',
              _Choice<PaneMode>(
                value: _shared(items.map((item) => item.pane!.mode)),
                choices: const {
                  PaneMode.flow: 'In order',
                  PaneMode.grid: 'On cells',
                  PaneMode.free: 'Anywhere',
                },
                onChanged: (mode) => panes((pane) => withMode(pane, mode)),
              ),
            ),
            _Stepper(
              label: 'Columns',
              value: _shared(items.map((item) => item.pane!.columns * 1.0)),
              min: 1,
              max: Pane.maxColumns,
              onChanged: (columns) =>
                  panes((pane) => withColumns(pane, columns)),
            ),
            _Stepper(
              label: 'Spacing',
              value: _shared(items.map((item) => item.pane!.spacing ?? -1)),
              usual: 'Usual',
              min: 0,
              max: Pane.maxSpacing.round(),
              step: 2,
              onChanged: (spacing) => panes(
                (pane) =>
                    pane.copyWith(spacing: spacing < 0 ? null : spacing * 1.0),
              ),
            ),
            _Stepper(
              label: 'Padding',
              value: _shared(items.map((item) => item.pane!.padding ?? -1)),
              usual: 'Usual',
              min: 0,
              max: Pane.maxPadding.round(),
              step: 2,
              onChanged: (padding) => panes(
                (pane) =>
                    pane.copyWith(padding: padding < 0 ? null : padding * 1.0),
              ),
            ),
            if (found.length == 1 && found.single.panel.kind == PanelKind.home)
              _Tick(
                label: 'New apps go here',
                value: ref.watch(inboxProvider) == items.single.pane!.id,
                onChanged: (here) {
                  if (here) {
                    change(
                      (layout) => withInbox(layout, items.single.pane!.id),
                    );
                  }
                },
              ),
          ]),
        ],
        if (allFolders && folders.length == found.length)
          _Section('Folder', [
            if (found.length == 1) ...[
              _Field(
                label: 'Name',
                value: folders.values.single.title,
                onChanged: (title) => change(
                  (layout) => changePanel(
                    layout,
                    items.single.ref,
                    (panel) => Panel(
                      id: panel.id,
                      title: title,
                      root: panel.root,
                      position: panel.position,
                      size: panel.size,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => TvScreen.openPopup(items.single.ref),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open it'),
                ),
              ),
            ],
            _Row(
              'Opens',
              _Choice<PopupPosition>(
                value: _shared(folders.values.map((panel) => panel.position)),
                choices: const {
                  PopupPosition.center: 'Centre',
                  PopupPosition.bottom: 'Bottom',
                  PopupPosition.left: 'Left',
                  PopupPosition.right: 'Right',
                },
                onChanged: (position) => change(
                  (layout) => folders.keys.fold(
                    layout,
                    (layout, id) => changePanel(
                      layout,
                      id,
                      (panel) => Panel(
                        id: panel.id,
                        title: panel.title,
                        root: panel.root,
                        position: position,
                        size: panel.size,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Row(
              'Size',
              _Choice<PopupSize>(
                value: _shared(folders.values.map((panel) => panel.size)),
                choices: const {
                  PopupSize.small: 'Small',
                  PopupSize.medium: 'Medium',
                  PopupSize.large: 'Large',
                },
                onChanged: (size) => change(
                  (layout) => folders.keys.fold(
                    layout,
                    (layout, id) => changePanel(
                      layout,
                      id,
                      (panel) => Panel(
                        id: panel.id,
                        title: panel.title,
                        root: panel.root,
                        position: panel.position,
                        size: size,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: FilledButton.tonalIcon(
            onPressed: () => removeSelected(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: Text(
              found.length == 1 ? 'Take it off the TV' : 'Take them off the TV',
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ...children,
      ],
    ),
  );
}

/// A setting with its name in front of it.
class _Row extends StatelessWidget {
  const _Row(this.label, this.child);

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
class _Stepper extends StatelessWidget {
  const _Stepper({
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
    return _Row(
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
class _Tick extends StatelessWidget {
  const _Tick({
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

class _Choice<T> extends StatelessWidget {
  const _Choice({
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

class _Slide extends StatefulWidget {
  const _Slide({
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value, max;
  final int divisions;
  final String label;
  final void Function(double value) onChanged;

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> {
  /// Where the thumb is while it is held; the change is made on letting go.
  double? _held;

  @override
  Widget build(BuildContext context) => Slider(
    value: (_held ?? widget.value).clamp(0, widget.max),
    max: widget.max,
    divisions: widget.divisions,
    label: _held == null ? widget.label : '${_held!.round()}°',
    onChanged: (value) => setState(() => _held = value),
    onChangeEnd: (value) {
      setState(() => _held = null);
      widget.onChanged(value);
    },
  );
}

/// A line of text that is taken when Enter is pressed or it is left.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label, value;
  final void Function(String value) onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
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
  void didUpdateWidget(_Field old) {
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
