import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// Action chains per trigger. An act is an entity and one of that entity's
/// actions, or an address; chains equal to [defaults] are not stored.
class TriggerSettings extends ConsumerStatefulWidget {
  const TriggerSettings({
    super.key,
    required this.set,
    required this.onChanged,
    this.defaults = const {},
    this.scope = const {},
    this.triggers = const [
      Trigger.press,
      Trigger.hold,
      Trigger.focus,
      Trigger.blur,
    ],
    this.title = 'Actions',
  });

  /// The stored chains, and its prefab's.
  final Triggers set, defaults;

  /// The variables it can read; an entity-typed one can be a target.
  final Variables scope;

  final List<Trigger> triggers;
  final String title;
  final void Function(Triggers set) onChanged;

  @override
  ConsumerState<TriggerSettings> createState() => _TriggerSettingsState();
}

class _TriggerSettingsState extends ConsumerState<TriggerSettings> {
  /// Triggers with a row whose entity is not chosen yet. Not saved.
  final _drafts = <Trigger>{};

  static final _variable = RegExp(r'^\{\{(\w+)\.id\}\}$');

  List<Act> _acts(Trigger trigger) =>
      widget.set[trigger] ?? widget.defaults[trigger] ?? const [];

  void _change(Trigger trigger, List<Act> acts) {
    final next = {...widget.set, trigger: acts};
    if (listEquals(acts, widget.defaults[trigger] ?? const [])) {
      next.remove(trigger);
    }
    widget.onChanged(next);
  }

  /// The entity id [target] stands for, where the editor can tell.
  String? _entityOf(String? target) {
    final name = _variable.firstMatch(target ?? '')?.group(1);
    if (name == null) return target;
    return switch (widget.scope[name]?.value) {
      final String id when !id.contains('{{') => id,
      _ => null,
    };
  }

  /// What an act can be aimed at, under headings: entity variables in scope,
  /// then every entity with an action, by pack, with the categories packs
  /// name and hold several of on their own. Saved targets are kept.
  Map<String, Map<String, String>> _targets(List<Entity> entities) {
    final acting = [
      for (final entity in entities)
        if (entity.actions.isNotEmpty) entity,
    ];
    final named = ref.watch(categoriesProvider);
    final packs = {
      for (final pack in ref.watch(packsProvider).value ?? const <Pack>[])
        pack.id: pack.name,
    };
    final sizes = <String, int>{};
    for (final entity in acting) {
      sizes[entity.category] = (sizes[entity.category] ?? 0) + 1;
    }
    bool alone(Entity entity) =>
        !named.containsKey(entity.category) || sizes[entity.category] == 1;
    final groups = <String, Map<String, String>>{
      'Variables': {
        for (final MapEntry(key: name, value: variable) in widget.scope.entries)
          if (variable.type == VarType.entity)
            '{{$name.id}}': switch (entities.byId(_entityOf('{{$name.id}}'))) {
              final entity? => '$name (${entity.label})',
              _ => name,
            },
      },
    };
    void add(String heading, Iterable<Entity> which) {
      if (which.isEmpty) return;
      groups[heading] = {
        ...?groups[heading],
        for (final entity in which) entity.id: entity.label,
      };
    }

    for (final entity in acting) {
      if (entity.category == userCategory) {
        add('Custom', [entity]);
      } else if (alone(entity)) {
        final pack = entity.id.contains(':')
            ? entity.id.substring(0, entity.id.indexOf(':'))
            : '';
        add(packs[pack] ?? (pack.isEmpty ? 'Other' : pack), [entity]);
      }
    }
    for (final MapEntry(key: category, value: label) in named.entries) {
      add(label, acting.where((e) => e.category == category && !alone(e)));
    }
    groups['Launcher'] = {
      ...?groups['Launcher'],
      ..._areas(Operation.launcher),
    };
    groups['TV'] = {...?groups['TV'], ..._areas(Operation.device)};
    for (final trigger in widget.triggers) {
      for (final act in _acts(trigger)) {
        final target = act.arg(entityArg);
        if (act.isAddress ||
            target == null ||
            groups.values.any((choices) => choices.containsKey(target))) {
          continue;
        }
        groups['Variables']![target] =
            _variable.firstMatch(target)?.group(1) ?? target;
      }
    }
    return groups;
  }

  /// The areas of addresses starting [scheme], shown as written.
  Map<String, String> _areas(String scheme) => {
    for (final area in ref.watch(operationsRegistryProvider).areas)
      if (area.startsWith(scheme)) area: area,
  };

  /// [from] aimed at [target], an entity or an area: the same action or
  /// operation where it has one, else its first. Null if it has none.
  Act? _aimed(String target, Act? from, List<Entity> entities) {
    if (target.contains('://')) {
      final there = ref.read(operationsRegistryProvider).inArea(target);
      if (there.isEmpty) return null;
      final operation =
          there.where((one) => one.name == from?.name).firstOrNull ??
          there.first;
      return Act(operation.name, {
        for (final MapEntry(:key, :value) in from?.args.entries ?? const [])
          if (operation.args.containsKey(key)) key: value,
      });
    }
    final offered = actionsOf(_entityOf(target), entities);
    if (offered.isEmpty) return null;
    final name = offered.containsKey(from?.name)
        ? from!.name
        : offered.keys.first;
    return from == null || from.isAddress
        ? Act(name, {entityArg: target})
        : retargeted(from, target, name, offered[name]);
  }

  Widget _remove(String tooltip, VoidCallback onPressed) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.delete_outline, size: 18),
    onPressed: onPressed,
  );

  /// An act's two dropdowns: side by side where there is room, else the
  /// action under the entity.
  Widget _pair(Widget entity, Widget action, VoidCallback onRemoved) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final remove = _remove('Remove action', onRemoved);
          return constraints.maxWidth >= 420
              ? Row(
                  children: [
                    Expanded(child: entity),
                    const SizedBox(width: 6),
                    Expanded(child: action),
                    remove,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: entity),
                        remove,
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: action,
                    ),
                  ],
                );
        },
      );

  /// Sets one act's fields apart from the next.
  Widget _act(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  /// One saved act: its entity and that entity's action, or an area and the
  /// operation there; then its arguments.
  Widget _row(
    Trigger trigger,
    int index,
    List<Entity> entities,
    Map<String, Map<String, String>> targets,
  ) {
    final acts = _acts(trigger);
    final act = acts[index];
    void put(Act? next) => _change(trigger, [
      for (final (i, one) in acts.indexed)
        if (i != index) one else ?next,
    ]);
    final registry = ref.watch(operationsRegistryProvider);
    final target = act.isAddress
        ? Operation.areaOf(act.name)
        : act.arg(entityArg);
    final actions = act.isAddress
        ? const <String, EntityAction>{}
        : actionsOf(_entityOf(target), entities);
    // What the second box offers, and what the chosen one is told.
    final offered = act.isAddress
        ? {for (final one in registry.inArea(target!)) one.name: one.label}
        : {
            for (final MapEntry(key: name, value: action) in actions.entries)
              name: action.label.isEmpty ? name : action.label,
          };
    final args = act.isAddress
        ? registry[act.name]?.args
        : actions[act.name]?.args;
    final theme = Theme.of(context);
    return _act([
      _pair(
        SearchBox(
          value: target,
          groups: targets,
          hint: 'Entity',
          onChanged: (next) {
            if (_aimed(next, act, entities) case final aimed?) put(aimed);
          },
        ),
        ChoiceBox<String>(
          value: act.name,
          hint: 'Action',
          choices: {
            // Keeps a saved one that is not there.
            if (args == null) act.name: act.name,
            ...offered,
          },
          onChanged: (name) => put(
            act.isAddress
                ? Act(name, {
                    for (final MapEntry(:key, :value) in act.args.entries)
                      if (registry[name]?.args.containsKey(key) ?? false)
                        key: value,
                  })
                : retargeted(act, target ?? '', name, actions[name]),
          ),
        ),
        () => put(null),
      ),
      if (args == null)
        Text(
          act.isAddress
              ? 'There is nothing at "${act.name}".'
              : 'This entity has no action "${act.name}".',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        )
      else if (args.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...optionFields(
          options: argOptions(args),
          values: {
            for (final MapEntry(:key, :value) in act.args.entries)
              if (key != entityArg) key: value,
          },
          onChanged: (told) => put(
            Act(act.name, {if (!act.isAddress) entityArg: target, ...told}),
          ),
        ),
      ],
    ]);
  }

  /// A new act with no entity yet; choosing one saves it with that entity's
  /// first action.
  Widget _draft(
    Trigger trigger,
    List<Entity> entities,
    Map<String, Map<String, String>> targets,
  ) => _act([
    _pair(
      SearchBox(
        value: null,
        groups: targets,
        hint: 'Entity',
        onChanged: (target) {
          final aimed = _aimed(target, null, entities);
          if (aimed == null) return;
          setState(() => _drafts.remove(trigger));
          _change(trigger, [..._acts(trigger), aimed]);
        },
      ),
      const ChoiceBox<String>(
        value: null,
        hint: 'Action',
        choices: {},
        onChanged: null,
      ),
      () => setState(() => _drafts.remove(trigger)),
    ),
  ]);

  List<Widget> _trigger(
    Trigger trigger,
    List<Entity> entities,
    Map<String, Map<String, String>> targets,
  ) {
    final theme = Theme.of(context);
    final acts = _acts(trigger);
    final inherits = widget.defaults[trigger]?.isNotEmpty ?? false;
    final own = widget.set.containsKey(trigger);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(trigger.label, style: theme.textTheme.labelLarge),
            ),
            if (inherits && !own)
              Text('From prefab', style: theme.textTheme.bodySmall),
            if (inherits && own)
              IconButton(
                tooltip: 'Reset to prefab',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt, size: 18),
                onPressed: () =>
                    widget.onChanged({...widget.set}..remove(trigger)),
              ),
            _remove('Remove trigger', () {
              setState(() => _drafts.remove(trigger));
              _change(trigger, const []);
            }),
          ],
        ),
      ),
      if (acts.isEmpty && inherits)
        Text('Prefab actions disabled', style: theme.textTheme.bodySmall),
      for (final index in Iterable<int>.generate(acts.length))
        _row(trigger, index, entities, targets),
      if (_drafts.contains(trigger)) _draft(trigger, entities, targets),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _drafts.contains(trigger)
              ? null
              : () => setState(() => _drafts.add(trigger)),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add action'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final targets = _targets(entities);
    final shown = [
      for (final trigger in widget.triggers)
        if (_acts(trigger).isNotEmpty ||
            widget.set.containsKey(trigger) ||
            _drafts.contains(trigger))
          trigger,
    ];
    final addable = [
      for (final trigger in widget.triggers)
        if (!shown.contains(trigger)) trigger,
    ];
    return Section(widget.title, open: false, [
      if (shown.isEmpty)
        Text('No triggers', style: Theme.of(context).textTheme.bodySmall),
      for (final trigger in shown) ..._trigger(trigger, entities, targets),
      if (shown.isNotEmpty && addable.isNotEmpty) const Divider(height: 16),
      if (addable.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<Trigger>(
            tooltip: 'Add trigger',
            onSelected: (trigger) => setState(() => _drafts.add(trigger)),
            itemBuilder: (context) => [
              for (final trigger in addable)
                PopupMenuItem(value: trigger, child: Text(trigger.label)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [Icon(Icons.add, size: 18), Text('Add trigger')],
              ),
            ),
          ),
        ),
    ]);
  }
}
