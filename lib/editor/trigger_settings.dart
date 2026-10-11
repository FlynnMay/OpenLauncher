import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';

/// Action chains per trigger. Offered actions are those entities define;
/// chains equal to [usual] are not stored.
class TriggerSettings extends ConsumerWidget {
  const TriggerSettings({
    super.key,
    required this.set,
    required this.usual,
    required this.onChanged,
    this.triggers = const [
      Trigger.press,
      Trigger.hold,
      Trigger.focus,
      Trigger.blur,
    ],
    this.title = 'Actions',
  });

  /// The stored chains and the defaults.
  final Triggers set, usual;

  final List<Trigger> triggers;
  final String title;
  final void Function(Triggers set) onChanged;

  void _change(Trigger trigger, List<Act> acts) {
    final next = {...set, trigger: acts};
    if (listEquals(acts, usual[trigger] ?? const [])) next.remove(trigger);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An action is offered the entities that present it.
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    // A new act, aimed at the first entity that can do it.
    Map<String, Object?> blank(String name) => {
      'do': name,
      entityArg: entitiesFor(name, entities).keys.first,
    };
    return Section(title, open: false, [
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
                blank: blank(actionLabels(entities).keys.firstOrNull ?? 'open'),
                fields: (act) => actOptions(act, entities: entities),
              ),
              records: [for (final act in acts) act.toJson()],
              onChanged: (told) => _change(trigger, [
                for (final (index, one) in told.indexed)
                  // Changing the action clears its arguments.
                  ?Act.fromJson(
                    told.length == acts.length && one['do'] != acts[index].name
                        ? blank('${one['do']}')
                        : one,
                  ),
              ]),
            ),
          ];
        }(),
    ]);
  }
}
