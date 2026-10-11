import 'package:flutter/material.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/trigger_settings.dart';
import 'package:openlauncher/editor/variables_settings.dart';

/// How one or more panes arrange what is in them: the same settings for a
/// pane on the screen and for the screen itself, which is a pane too.
class PaneSettings extends StatelessWidget {
  const PaneSettings({
    super.key,
    required this.title,
    required this.panes,
    required this.onChanged,
    this.named = true,
    this.children = const [],
    this.prefabs = const {},
    this.usualOn,
  });

  /// The heading the settings go under.
  final String title;
  final List<Pane> panes;

  /// Called with how each of the panes is to change.
  final void Function(Pane Function(Pane pane) change) onChanged;

  /// Whether a pane's own title is among its settings.
  final bool named;

  /// The prefabs there are, by id, for the rules a pane has for each;
  /// with none given, rules are not offered.
  final Map<String, Prefab> prefabs;

  /// What the pane does when it is revealed and hidden where it says
  /// nothing itself, for a pane that is: a sidebar's, a folder's. With
  /// none given, that is not offered.
  final Triggers? usualOn;

  /// More settings, shown after these.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _arrangement,
      _entities,
      if (prefabs.isNotEmpty) _rules,
      if (usualOn case final usual? when panes.length == 1)
        TriggerSettings(
          title: 'When it is shown and hidden',
          triggers: const [Trigger.reveal, Trigger.hide],
          set: panes.single.on,
          usual: usual,
          onChanged: (on) => onChanged((pane) => pane.copyWith(on: on)),
        ),
      // What everything in the pane can read; one pane at a time.
      if (panes.length == 1)
        VariablesSettings(
          variables: panes.single.vars,
          onChanged: (vars) => onChanged((pane) => pane.copyWith(vars: vars)),
        ),
    ],
  );

  /// Its rules, each drawn from what describes it. With several panes
  /// they show the first one's, and a change is made to them all.
  Widget get _arrangement => Section(title, [
    ...ruleFields(
      options: [
        for (final rule in paneRules)
          if (rule.key != 'title' || named && panes.length == 1) rule,
      ],
      json: {...panes.first.toJson(), ...panes.first.rules},
      onChanged: (key, value) =>
          onChanged((pane) => withRule(pane, key, value)),
    ),
    ...children,
  ]);

  /// This pane's rule for [prefab] with [key] set to [value]; null takes
  /// it away, and a rule with nothing left in it goes too.
  static Pane _ruled(Pane pane, String prefab, String key, Object? value) {
    final rule = {...?pane.prefabRules[prefab], key: value}
      ..removeWhere((_, value) => value == null);
    return pane.copyWith(
      prefabRules: {
        for (final MapEntry(:key, :value) in pane.prefabRules.entries)
          if (key != prefab) key: value,
        if (rule.isNotEmpty) prefab: rule,
      },
    );
  }

  static bool _builtIn(Prefab prefab) =>
      builtInPrefabs.any((own) => own.id == prefab.id);

  /// What the pane says of the instances of prefabs directly in it. The
  /// launcher's own prefabs always have their rule here, so that there is
  /// somewhere to say how the entities of a pane are laid out; a rule for a
  /// prefab of the user's is there once it is added.
  Widget get _rules {
    bool ruled(Prefab prefab) =>
        panes.any((pane) => pane.prefabRules.containsKey(prefab.id));
    final shown = [
      for (final prefab in prefabs.values)
        if (_builtIn(prefab) || ruled(prefab)) prefab,
    ];
    final addable = [
      for (final prefab in prefabs.values)
        if (!shown.contains(prefab) && prefab.layouts.isNotEmpty) prefab,
    ];
    return Section('Prefab rules', open: false, [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'For everything in this pane made from a prefab. A rule counts '
          'over what each says for itself.',
        ),
      ),
      for (final prefab in shown) ..._rule(prefab),
      if (addable.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<Prefab>(
            tooltip: 'Add a rule for a prefab',
            // A rule has to say something to be one: it starts with the
            // prefab's first layout.
            onSelected: (prefab) => onChanged(
              (pane) => _ruled(
                pane,
                prefab.id,
                layoutOption,
                prefab.layouts.keys.first,
              ),
            ),
            itemBuilder: (context) => [
              for (final prefab in addable)
                PopupMenuItem(value: prefab, child: Text(prefab.name)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [Icon(Icons.add, size: 18), Text('Add a rule')],
              ),
            ),
          ),
        ),
    ]);
  }

  /// The rule for [prefab]: its layout, and whether each part shows.
  List<Widget> _rule(Prefab prefab) => [
    LabelledRow(
      prefab.name,
      ChoiceBox<String>(
        value: shared(
          panes.map(
            (pane) => switch (pane.prefabRules[prefab.id]?[layoutOption]) {
              final String layout when prefab.layouts.containsKey(layout) =>
                layout,
              _ => _each,
            },
          ),
        ),
        choices: {
          // The launcher's own may leave it to each entity; a rule that
          // was added says which, or is taken away.
          // One that says no layout, as a save may, can be given one.
          if (_builtIn(prefab) ||
              panes.any(
                (pane) => pane.prefabRules[prefab.id]?[layoutOption] == null,
              ))
            _each: 'As each says',
          for (final MapEntry(:key, :value) in prefab.layouts.entries)
            key: value.label.isEmpty ? key : value.label,
        },
        onChanged: (layout) => onChanged(
          (pane) => _ruled(
            pane,
            prefab.id,
            layoutOption,
            layout == _each ? null : layout,
          ),
        ),
      ),
    ),
    for (final part in prefab.parts.keys)
      LabelledRow(
        '  $part',
        ChoiceBox<String>(
          value: shared(
            panes.map(
              (pane) => switch (overridesOf(
                LayoutItem(
                  id: '',
                  kind: ItemKind.prefab,
                  ref: '',
                  options: pane.prefabRules[prefab.id] ?? const {},
                ),
                part,
              )[hiddenOption]) {
                true => 'hidden',
                false => 'shown',
                _ => _each,
              },
            ),
          ),
          choices: const {
            _each: 'As each says',
            'shown': 'Shown',
            'hidden': 'Hidden',
          },
          onChanged: (shown) => onChanged((pane) {
            final rule = withOverrides(
              pane.prefabRules[prefab.id] ?? const {},
              part,
              {
                hiddenOption: switch (shown) {
                  'shown' => false,
                  'hidden' => true,
                  _ => null,
                },
              },
            );
            return _ruled(pane, prefab.id, partsOption, rule[partsOption]);
          }),
        ),
      ),
    if (!_builtIn(prefab))
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => onChanged(
            (pane) => pane.copyWith(
              prefabRules: {
                for (final MapEntry(:key, :value) in pane.prefabRules.entries)
                  if (key != prefab.id) key: value,
              },
            ),
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Take the rule for ${prefab.name} away'),
        ),
      ),
  ];

  /// The size the pane gives every entity directly in it.
  Widget get _entities => Section('Size of what is in it', open: false, [
    TickBox(
      label: 'All the same size',
      value: shared(panes.map((pane) => pane.itemW != null)),
      onChanged: (same) => onChanged(
        (pane) => pane
            .withRule('itemW', same ? pane.itemW ?? 1 : null)
            .withRule('itemH', same ? pane.itemH ?? 1 : null),
      ),
    ),
    if (panes.every((pane) => pane.itemW != null)) ...[
      NumberStepper(
        label: 'Cells wide',
        value: shared(panes.map((pane) => pane.itemW!)),
        min: 1,
        max: panes.map((pane) => pane.columns).reduce((a, b) => a < b ? a : b),
        onChanged: (w) => onChanged((pane) => pane.withRule('itemW', w)),
      ),
      NumberStepper(
        label: 'Cells tall',
        value: shared(panes.map((pane) => pane.itemH ?? 1)),
        min: 1,
        max: Pane.maxRows,
        onChanged: (h) => onChanged((pane) => pane.withRule('itemH', h)),
      ),
    ],
  ]);

  /// Stands for "the pane does not decide" among the choices.
  static const _each = 'each';
}
