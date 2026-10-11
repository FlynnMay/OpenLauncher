import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';

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

  void _change(Trigger trigger, List<Act> acts) {
    final next = {...set, trigger: acts};
    if (listEquals(acts, usual[trigger] ?? const [])) next.remove(trigger);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) => Section(title, open: false, [
    for (final trigger in triggers)
      ...() {
        final acts = set[trigger] ?? usual[trigger] ?? const <Act>[];
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              trigger.label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ListField(
            option: ComponentOption(
              trigger.name,
              acts.isEmpty ? 'Add an action' : 'Then another',
              OptionKind.list,
              blank: {'do': actionKinds.first.name},
              fields: (act) => actOptions(act, entities: entities),
            ),
            records: [for (final act in acts) act.toJson()],
            onChanged: (told) => _change(trigger, [
              for (final (index, one) in told.indexed)
                // Another action is told nothing of what the last was.
                ?Act.fromJson(
                  told.length == acts.length && one['do'] != acts[index].name
                      ? {'do': one['do']}
                      : one,
                ),
            ]),
          ),
        ];
      }(),
  ]);
}
