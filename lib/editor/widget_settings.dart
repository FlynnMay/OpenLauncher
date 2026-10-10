import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/controls.dart';
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
    final settings = switch (kind) {
      WidgetKind.clock => [
        TickBox(
          label: '24-hour',
          value: options['hour24'] != false,
          onChanged: (on) => _set('hour24', on),
        ),
        TickBox(
          label: 'Show the date',
          value: options['date'] != false,
          onChanged: (on) => _set('date', on),
        ),
        TickBox(
          label: 'Show seconds',
          value: options['seconds'] == true,
          onChanged: (on) => _set('seconds', on),
        ),
      ],
      WidgetKind.weather => [
        _PlaceSearch(
          place: options['place'] as String?,
          onChosen: (place) => onChanged({
            ...options,
            'place': place.name,
            'latitude': place.latitude,
            'longitude': place.longitude,
          }),
        ),
        TickBox(
          label: 'Fahrenheit',
          value: options['fahrenheit'] == true,
          onChanged: (on) => _set('fahrenheit', on),
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
      null => const <Widget>[],
    };
    if (settings.isEmpty) return const SizedBox.shrink();
    return Section(kind?.label ?? 'Widget', settings);
  }
}

/// Finds a place by name and offers what was found.
class _PlaceSearch extends ConsumerStatefulWidget {
  const _PlaceSearch({required this.place, required this.onChosen});

  final String? place;
  final void Function(Place place) onChosen;

  @override
  ConsumerState<_PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends ConsumerState<_PlaceSearch>
    with Busy<_PlaceSearch> {
  List<Place>? _found;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(switch (widget.place) {
          null => 'No place chosen yet',
          final place => 'Weather for $place',
        }),
      ),
      TextField(
        decoration: InputDecoration(
          labelText: 'Town or city',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search),
        ),
        onSubmitted: (name) {
          if (name.trim().isEmpty) return;
          whileBusy(() async {
            final found = await ref.read(tvApiProvider).findPlaces(name.trim());
            if (mounted) setState(() => _found = found);
          });
        },
      ),
      if (_found case final found?)
        if (found.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No place found by that name.'),
          )
        else
          for (final place in found)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(place.name),
              onTap: () {
                setState(() => _found = null);
                widget.onChosen(place);
              },
            ),
    ],
  );
}
