import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// Visible as a tick, and while on, an expression that must hold; then
/// whether the others close up when it is hidden.
class VisibilityFields extends StatelessWidget {
  const VisibilityFields({
    super.key,
    required this.visible,
    required this.keep,
    required this.onVisible,
    required this.onKeep,
    this.when = true,
    this.canKeep = true,
  });

  /// `false`, an expression, or anything else for always; null where the
  /// nodes differ.
  final Object? visible;
  final bool? keep;

  /// Called with `false`, `true`, or an expression.
  final void Function(Object visible) onVisible;
  final void Function(bool keep) onKeep;

  /// Whether the expression can be edited (not for several nodes at once).
  final bool when;

  /// Whether there is a layout around it for keeping its space to mean
  /// anything.
  final bool canKeep;

  @override
  Widget build(BuildContext context) {
    final shown = visible != false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TickBox(
          label: 'Visible',
          value: shown,
          onChanged: (shown) => onVisible(shown),
        ),
        if (shown && when)
          TemplateField(
            label: 'Visible when',
            value: visible is String ? visible! as String : '',
            onChanged: onVisible,
          ),
        if (canKeep)
          TickBox(
            label: 'Keep space when hidden',
            value: keep ?? false,
            onChanged: onKeep,
          ),
      ],
    );
  }
}

/// The Visibility section: every node has it.
List<Widget> visibilityEditor(ModuleEdit edit) {
  final visible = [
    for (final node in edit.drawn) node.modules['visibility']?['visible'],
  ];
  return [
    VisibilityFields(
      visible: visible.toSet().length == 1 ? visible.first : null,
      when: edit.single,
      keep: shared(edit.drawn.map((node) => node.keep)),
      canKeep:
          edit.parents.isNotEmpty &&
          edit.parents.every((parent) => parent.mode != LayoutMode.free),
      onVisible: (visible) => edit.set(
        'visible',
        visible == true || visible == '' ? null : visible,
      ),
      onKeep: (keep) => edit.set('keep', keep ? true : null),
    ),
  ];
}
