import 'package:flutter/material.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/template_field.dart';

/// The variables of one component: each named, with what it is, who may
/// read it, and, for one that is conditional, what it looks at and what it
/// is for each case. Knows nothing of what the component is.
class VariablesSettings extends StatelessWidget {
  const VariablesSettings({
    super.key,
    required this.variables,
    required this.onChanged,
    this.note,
  });

  final Variables variables;
  final void Function(Variables variables) onChanged;

  /// Said under the heading, where there is something to say of them.
  final String? note;

  void _put(String name, Variable? variable) => onChanged({
    for (final MapEntry(:key, :value) in variables.entries)
      if (key != name) key: value else key: ?variable,
    if (variable != null && !variables.containsKey(name)) name: variable,
  });

  static String _text(Object? value) => value == null ? '' : '$value';

  /// What was typed as what it stands for: a number where it is one.
  static Object? _typed(String text) =>
      text.isEmpty ? null : num.tryParse(text) ?? text;

  Variable _with(
    Variable variable, {
    Object? value,
    VarAccess? access,
    String? when,
    List<VarCase>? cases,
    Object? otherwise,
    bool conditional = true,
    bool clear = false,
  }) => Variable(
    clear ? value : value ?? variable.value,
    access: access ?? variable.access,
    when: conditional ? when ?? variable.when : null,
    cases: cases ?? variable.cases,
    otherwise: clear ? otherwise : otherwise ?? variable.otherwise,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Section('Variables', open: false, [
      if (note case final note?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(note, style: theme.textTheme.bodySmall),
        ),
      for (final MapEntry(key: name, value: variable) in variables.entries) ...[
        Row(
          children: [
            Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
            IconButton(
              tooltip: 'Take $name away',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _put(name, null),
            ),
          ],
        ),
        LabelledRow(
          'Read by',
          ChoiceBox<VarAccess>(
            value: variable.access,
            choices: {
              for (final access in VarAccess.values) access: access.label,
            },
            onChanged: (access) => _put(name, _with(variable, access: access)),
          ),
        ),
        TickBox(
          label: 'Depends on something',
          value: variable.isConditional,
          onChanged: (on) => _put(
            name,
            _with(variable, when: on ? '' : null, conditional: on),
          ),
        ),
        if (!variable.isConditional)
          TemplateField(
            label: 'Is',
            value: _text(variable.value),
            onChanged: (text) =>
                _put(name, _with(variable, value: _typed(text), clear: true)),
          )
        else ...[
          TemplateField(
            label: 'Looks at',
            value: variable.when ?? '',
            onChanged: (when) => _put(name, _with(variable, when: when)),
          ),
          for (final (index, entry) in variable.cases.indexed) ...[
            Row(
              children: [
                const Text('When it '),
                Expanded(
                  child: ChoiceBox<VarTest>(
                    value: entry.test,
                    choices: {
                      for (final test in VarTest.values) test: test.label,
                    },
                    onChanged: (test) => _put(
                      name,
                      _with(
                        variable,
                        cases: [
                          for (final (i, old) in variable.cases.indexed)
                            i == index
                                ? VarCase(test, old.value, old.then)
                                : old,
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Take this case away',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _put(
                    name,
                    _with(
                      variable,
                      cases: [
                        for (final (i, old) in variable.cases.indexed)
                          if (i != index) old,
                      ],
                    ),
                  ),
                ),
              ],
            ),
            CommitField(
              label: 'this',
              value: _text(entry.value),
              onChanged: (text) => _put(
                name,
                _with(
                  variable,
                  cases: [
                    for (final (i, old) in variable.cases.indexed)
                      i == index
                          ? VarCase(old.test, _typed(text), old.then)
                          : old,
                  ],
                ),
              ),
            ),
            CommitField(
              label: 'it is',
              value: _text(entry.then),
              onChanged: (text) => _put(
                name,
                _with(
                  variable,
                  cases: [
                    for (final (i, old) in variable.cases.indexed)
                      i == index
                          ? VarCase(old.test, old.value, _typed(text))
                          : old,
                  ],
                ),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _put(
                name,
                _with(
                  variable,
                  cases: [
                    ...variable.cases,
                    const VarCase(VarTest.equals, null, null),
                  ],
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a case'),
            ),
          ),
          CommitField(
            label: 'Otherwise it is',
            value: _text(variable.otherwise),
            onChanged: (text) => _put(
              name,
              _with(variable, otherwise: _typed(text), clear: true),
            ),
          ),
        ],
        const Divider(height: 24),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final name = await askName(
              context,
              'name',
              title: 'Name of the variable',
            );
            // As it is written in a template: one word.
            final word = name?.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
            if (word == null || word.isEmpty || variables.containsKey(word)) {
              return;
            }
            _put(word, const Variable(null));
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a variable'),
        ),
      ),
    ]);
  }
}
