import 'package:flutter/material.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/editor/controls.dart';

/// What a thing does, by what sets it off: for each trigger, the action
/// and whatever that action is told. Everything offered is read from
/// `actionKinds`. What is the same as the [usual] is not kept as set.
class TriggerSettings extends StatelessWidget {
  const TriggerSettings({
    super.key,
    required this.set,
    required this.usual,
    required this.panels,
    required this.cards,
    required this.onChanged,
  });

  /// What was set for the thing, and what it does where nothing was.
  final Triggers set, usual;

  /// The popups and the cards there are, by id, with what each is called.
  final Map<String, String> panels, cards;
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

  @override
  Widget build(BuildContext context) => Section('Actions', open: false, [
    for (final trigger in Trigger.values)
      ...() {
        final acts = set[trigger] ?? usual[trigger] ?? const <Act>[];
        final act = acts.firstOrNull;
        final kind = act == null ? null : actionKind(act.name);
        Act told(String key, String? value) => Act(
          act!.name,
          {...act.args, key: ?value}
            ..removeWhere((name, _) => name == key && value == null),
        );
        return [
          LabelledRow(
            trigger.label,
            ChoiceBox<String>(
              value: kind?.name ?? _nothing,
              choices: {
                _nothing: 'Nothing',
                for (final kind in actionKinds) kind.name: kind.label,
              },
              onChanged: (name) =>
                  _change(trigger, [if (name != _nothing) Act(name)]),
            ),
          ),
          if (act != null && kind != null) ...[
            if (kind.needs != Needs.nothing)
              LabelledRow(
                '  to',
                ChoiceBox<String>(
                  value: cards.containsKey(act.arg('card'))
                      ? act.arg('card')
                      : _nothing,
                  choices: {_nothing: 'The card it belongs to', ...cards},
                  onChanged: (id) => _change(trigger, [
                    told('card', id == _nothing ? null : id),
                  ]),
                ),
              ),
            for (final MapEntry(key: name, value: choices) in kind.args.entries)
              LabelledRow(
                '  $name',
                ChoiceBox<String>(
                  value: switch (act.arg(name)) {
                    final String value
                        when name == panelArg
                            ? panels.containsKey(value)
                            : choices.contains(value) =>
                      value,
                    _ => null,
                  },
                  choices: name == panelArg
                      ? panels
                      : {for (final choice in choices) choice: choice},
                  onChanged: (value) => _change(trigger, [told(name, value)]),
                ),
              ),
            if (acts.length > 1)
              Text('and ${acts.length - 1} more after it, set in the layout'),
          ],
        ];
      }(),
  ]);
}
