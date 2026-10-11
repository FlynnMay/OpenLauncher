import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/place_search.dart';
import 'package:openlauncher/editor/template_field.dart';
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

  /// What a text widget does with text too long for its box.
  static const _overflows = {
    'fade': 'Fades out',
    'ellipsis': 'Cut short with …',
    'clip': 'Cut off',
    'wrap': 'Goes onto more lines',
    'scroll': 'Moves along',
  };

  String _text(String key) => switch (item.options[key]) {
    final String text => text,
    _ => '',
  };

  double _number(String key, double usual) => switch (item.options[key]) {
    final num number => number.toDouble(),
    _ => usual,
  };

  /// White until another colour is chosen.
  Widget _colour(String label) => LabelledRow(
    label,
    Align(
      alignment: Alignment.centerLeft,
      child: ColourChip(
        colour: BoxStyle.parseColor(item.options['colour']) ?? 0xFFFFFFFF,
        onChanged: (next) =>
            _set('colour', next == null ? null : BoxStyle.colorToCss(next)),
      ),
    ),
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
      WidgetKind.text => [
        TemplateField(
          label: 'Text',
          value: _text('text'),
          onChanged: (text) => _set('text', text),
        ),
        NumberStepper(
          label: 'Letter size',
          value: _number('size', 0),
          min: 8,
          max: 200,
          step: 2,
          usual: 'Fills the box',
          onChanged: (size) => _set('size', size < 8 ? null : size),
        ),
        // Text made to fill the box is never too long for it.
        if (options['size'] is num) ...[
          LabelledRow(
            'Too long',
            ChoiceBox<String>(
              value: switch (options['overflow']) {
                final String overflow when _overflows.containsKey(overflow) =>
                  overflow,
                _ => 'fade',
              },
              choices: _overflows,
              onChanged: (overflow) => _set('overflow', overflow),
            ),
          ),
          if (options['overflow'] == 'scroll')
            NumberStepper(
              label: 'Moves',
              value: _number('speed', 40),
              min: 10,
              max: 300,
              step: 10,
              onChanged: (speed) => _set('speed', speed),
            ),
        ],
        LabelledRow(
          'Sits',
          ChoiceBox<String>(
            value: switch (options['align']) {
              'left' => 'left',
              'right' => 'right',
              _ => 'center',
            },
            choices: const {
              'left': 'Left',
              'center': 'In the middle',
              'right': 'Right',
            },
            onChanged: (align) => _set('align', align),
          ),
        ),
        TickBox(
          label: 'Bold',
          value: options['bold'] == true,
          onChanged: (on) => _set('bold', on ? true : null),
        ),
        _colour('Colour'),
      ],
      WidgetKind.picture => [
        TemplateField(
          label: 'Web address or value',
          value: _text('source'),
          onChanged: (source) => _set('source', source),
        ),
        TickBox(
          label: 'Show all of it',
          value: options['fit'] == 'contain',
          onChanged: (on) => _set('fit', on ? 'contain' : null),
        ),
        NumberStepper(
          label: 'Round corners',
          value: _number('round', 6),
          min: 0,
          max: 120,
          step: 2,
          onChanged: (round) => _set('round', round),
        ),
      ],
      WidgetKind.meter => [
        TemplateField(
          label: 'Value',
          value: _text('value'),
          onChanged: (value) => _set('value', value),
        ),
        // Whole numbers here; a value of another scale is brought to one
        // with `| times:`.
        NumberStepper(
          label: 'Empty at',
          value: _number('min', 0),
          min: -1000,
          max: 100000,
          onChanged: (min) => _set('min', min),
        ),
        NumberStepper(
          label: 'Full at',
          value: _number('max', 100),
          min: -1000,
          max: 100000,
          onChanged: (max) => _set('max', max),
        ),
        LabelledRow(
          'Drawn as',
          ChoiceBox<String>(
            value: options['shape'] == 'ring' ? 'ring' : 'bar',
            choices: const {'bar': 'A bar', 'ring': 'A ring'},
            onChanged: (shape) => _set('shape', shape),
          ),
        ),
        _colour('Colour'),
      ],
      null => const <Widget>[],
    };
    if (settings.isEmpty) return const SizedBox.shrink();
    return Section(kind?.label ?? 'Widget', settings);
  }
}
