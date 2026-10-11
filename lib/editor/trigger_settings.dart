import 'package:flutter/material.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/editor/controls.dart';

/// What a thing does, by what sets it off: for each trigger, the actions
/// in the order they are done, each with whatever it is told. Everything
/// offered is read from `actionKinds`. What is the same as the [usual] is
/// not kept as set.
class TriggerSettings extends StatelessWidget {
  const TriggerSettings({
    super.key,
    required this.set,
    required this.usual,
    required this.onChanged,
    this.entities = const {},
    this.triggers = const [
      Trigger.press,
      Trigger.hold,
      Trigger.focus,
      Trigger.blur,
    ],
    this.title = 'Actions',
  });

  /// What was set for the thing, and what it does where nothing was.
  final Triggers set, usual;

  /// The entities there are, by id, with what each is called.
  final Map<String, String> entities;

  /// The triggers the thing has.
  final List<Trigger> triggers;
  final String title;
  final void Function(Triggers set) onChanged;

  static const _nothing = '';

  void _change(Trigger trigger, List<Act> acts) {
    final next = {...set, trigger: acts};
    // Back to what it would do anyway: nothing to keep.
    if (_same(acts, usual[trigger] ?? const [])) next.remove(trigger);
    onChanged(next);
  }

  static bool _same(List<Act> a, List<Act> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  /// The settings of the action at [index] of [acts], those [trigger] sets
  /// off: which it is, and what it is told.
  List<Widget> _act(Trigger trigger, List<Act> acts, int index) {
    final act = acts[index];
    final kind = actionKind(act.name);
    void put(Act? next) => _change(trigger, [
      for (final (i, old) in acts.indexed)
        if (i != index) old else ?next,
    ]);
    Act told(String key, Object? value) => Act(
      act.name,
      {...act.args, key: value}..removeWhere((_, value) => value == null),
    );
    return [
      Row(
        children: [
          Expanded(
            child: ChoiceBox<String>(
              value: kind?.name,
              choices: {for (final kind in actionKinds) kind.name: kind.label},
              onChanged: (name) => put(Act(name)),
            ),
          ),
          IconButton(
            tooltip: 'Take this action away',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => put(null),
          ),
        ],
      ),
      if (kind != null) ...[
        if (actionNeedsEntity(kind.name) && entities.isNotEmpty)
          LabelledRow(
            '  to',
            ChoiceBox<String>(
              value: entities.containsKey(act.arg(entityArg))
                  ? act.arg(entityArg)
                  : _nothing,
              choices: {_nothing: 'Its own source', ...entities},
              onChanged: (id) =>
                  put(told(entityArg, id == _nothing ? null : id)),
            ),
          ),
        for (final MapEntry(key: name, value: choices) in kind.args.entries)
          // One of the choices there are, or whatever is typed.
          if (choices.isEmpty)
            CommitField(
              label: name == 'of' ? 'of (an id; empty for itself)' : name,
              value: switch (act.args[name]) {
                null => '',
                final value => '$value',
              },
              onChanged: (text) => put(
                told(name, switch (text) {
                  '' => null,
                  'true' => true,
                  'false' => false,
                  _ => num.tryParse(text) ?? text,
                }),
              ),
            )
          else
            LabelledRow(
              '  $name',
              ChoiceBox<String>(
                value: switch (act.arg(name)) {
                  final String value when choices.contains(value) => value,
                  _ => null,
                },
                choices: {for (final choice in choices) choice: choice},
                onChanged: (value) => put(told(name, value)),
              ),
            ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Section(title, open: false, [
      for (final trigger in triggers)
        ...() {
          final acts = set[trigger] ?? usual[trigger] ?? const <Act>[];
          return [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(trigger.label, style: theme.textTheme.labelLarge),
            ),
            if (acts.isEmpty) Text('Nothing', style: theme.textTheme.bodySmall),
            // Done one after another, in this order.
            for (var index = 0; index < acts.length; index++)
              ..._act(trigger, acts, index),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _change(trigger, [...acts, Act(actionKinds.first.name)]),
                icon: const Icon(Icons.add, size: 18),
                label: Text(acts.isEmpty ? 'Add an action' : 'Then another'),
              ),
            ),
          ];
        }(),
    ]);
  }
}
