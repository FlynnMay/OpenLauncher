import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/tv_api.dart';

/// The settings of one primitive component.
class ComponentSettings extends ConsumerWidget {
  const ComponentSettings({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final Component item;

  final void Function(Map<String, Object?> options) onChanged;

  void _set(String key, Object? value) => onChanged(
    {...item.options, key: value}..removeWhere((_, v) => v == null),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = item.options;
    final state = ref.watch(tvStateProvider).value;
    final kind = ComponentKind.named(item.kind);
    final settings = [
      // Fields that need more than a generated one.
      ...switch (kind) {
        ComponentKind.android => [
          LabelledRow(
            'Shows',
            ChoiceBox<String>(
              value: switch (options['provider']) {
                final String id
                    when state?.widgetProviders.containsKey(id) ?? false =>
                  id,
                _ => null,
              },
              choices: state?.widgetProviders ?? const {},
              onChanged: (id) => _set('provider', id),
            ),
          ),
          const Text('It is shown on the TV, but the remote cannot select it.'),
        ],
        _ => const <Widget>[],
      },
      // The rest is generated from the kind's options.
      ...optionFields(
        options: kind?.options ?? const [],
        values: options,
        onChanged: onChanged,
      ),
    ];
    if (settings.isEmpty) return const SizedBox.shrink();
    return Section(kind?.label ?? 'Component', settings);
  }
}
