import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/tv_api.dart';

/// What one component on the screen is set to show; different for each kind
/// of component, and nothing at all for a kind with nothing to set.
class ComponentSettings extends ConsumerWidget {
  const ComponentSettings({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final LayoutItem item;

  /// Called with the component's options as they are to be.
  final void Function(Map<String, Object?> options) onChanged;

  void _set(String key, Object? value) => onChanged(
    {...item.options, key: value}..removeWhere((_, v) => v == null),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = item.options;
    final state = ref.watch(tvStateProvider).value;
    final kind = ComponentKind.named(item.ref);
    final settings = [
      // What takes more than a plain setting: a search, a list the TV has.
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
      // Everything else is read from what the kind says can be set.
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
