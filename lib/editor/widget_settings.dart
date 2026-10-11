import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/place_search.dart';
import 'package:openlauncher/editor/tv_api.dart';

/// What one widget on the screen is set to show; different for each kind
/// of widget, and nothing at all for a kind with nothing to set.
class WidgetSettings extends ConsumerWidget {
  const WidgetSettings({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final LayoutItem item;

  /// Called with the widget's options as they are to be.
  final void Function(Map<String, Object?> options) onChanged;

  void _set(String key, Object? value) => onChanged(
    {...item.options, key: value}..removeWhere((_, v) => v == null),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = item.options;
    final state = ref.watch(tvStateProvider).value;
    final kind = WidgetKind.named(item.ref);
    final settings = [
      // What takes more than a plain setting: a search, a list the TV has.
      ...switch (kind) {
        WidgetKind.weather => [
          PlaceSearch(
            said: switch (options['place']) {
              final String place => 'Weather for $place',
              _ => 'No place chosen yet',
            },
            onChosen: (place) => onChanged({
              ...options,
              'place': place.name,
              'latitude': place.latitude,
              'longitude': place.longitude,
            }),
          ),
        ],
        WidgetKind.android => [
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
        WidgetKind.media => [
          if (state?.notificationAccess == false)
            const Text(
              'Needs "Set up automatically" in the TV\'s Settings before it '
              'can see what is playing.',
            ),
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
    return Section(kind?.label ?? 'Widget', settings);
  }
}
