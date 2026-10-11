import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/widgets/weather.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/place_search.dart';

/// The values text on the screen can be made of: those the launcher has of
/// its own, with how each reads now, the place two of them go by, and
/// those the user defined, which are added, changed and taken away here.
class ValuesSettings extends ConsumerWidget {
  const ValuesSettings({
    super.key,
    required this.sources,
    required this.place,
    required this.onSources,
    required this.onPlace,
  });

  final List<DataSource> sources;
  final Place? place;
  final void Function(List<DataSource> sources) onSources;
  final void Function(Place? place) onPlace;

  /// How many single things of a value are listed under it.
  static const _mostParts = 12;

  void _change(DataSource source, DataSource changed) =>
      onSources([for (final one in sources) one == source ? changed : one]);

  Future<void> _add(BuildContext context) async {
    final name = await askName(context, 'Value', title: 'Name of the value');
    if (name == null || name.isEmpty) return;
    // Its id is how a template names it, and stays as it is made here.
    final id = freeId(slugOf(name, 'value'), {
      ...builtInRoots,
      for (final source in sources) source.id,
    });
    onSources([...sources, DataSource(id: id, name: name)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget reading(String path, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SelectableText('{{$path}}', style: small)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valueText(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    return Section('Values', open: false, [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Written into a Text, Picture or Meter widget between double '
          'braces, each is replaced by what it is at the time.',
        ),
      ),
      for (final value in builtInValues)
        reading(value.root, ref.watch(valueProvider(value.root))),
      const SizedBox(height: 12),
      PlaceSearch(
        said: switch (place) {
          null => 'Location and weather need a place.',
          final place => 'Location and weather are for ${place.name}',
        },
        onChosen: onPlace,
      ),
      if (place != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onPlace(null),
            child: const Text('Forget the place'),
          ),
        ),
      for (final source in sources) ...[
        const Divider(height: 24),
        CommitField(
          label: 'Name',
          value: source.name,
          onChanged: (name) => _change(source, source.copyWith(name: name)),
        ),
        LabelledRow(
          'Comes from',
          ChoiceBox<SourceKind>(
            value: source.kind,
            choices: {for (final kind in SourceKind.values) kind: kind.label},
            onChanged: (kind) => _change(source, source.copyWith(kind: kind)),
          ),
        ),
        if (source.kind == SourceKind.text)
          CommitField(
            label: 'Text',
            value: source.text,
            onChanged: (text) => _change(source, source.copyWith(text: text)),
          )
        else ...[
          CommitField(
            label: 'Web address',
            value: source.url,
            onChanged: (url) => _change(source, source.copyWith(url: url)),
          ),
          if (source.url.isNotEmpty && source.address == null)
            Text(
              'It has to start with http:// or https://',
              style: small?.copyWith(color: theme.colorScheme.error),
            ),
          NumberStepper(
            label: 'Asked every',
            value: source.every * 1.0,
            min: DataSource.minEvery,
            max: 3600,
            step: 10,
            onChanged: (every) =>
                _change(source, source.copyWith(every: every)),
          ),
          Text('seconds, by the TV, while something shows it.', style: small),
        ],
        const SizedBox(height: 6),
        // What it is now, one single thing to a line.
        ...switch (valuePaths(source.id, ref.watch(valueProvider(source.id)))) {
          final parts when parts.values.every((part) => part == null) => [
            reading(source.id, null),
            if (source.kind == SourceKind.http && source.address != null)
              Text('Nothing has come from it yet.', style: small),
          ],
          final parts => [
            for (final MapEntry(key: path, :value) in parts.entries.take(
              _mostParts,
            ))
              reading(path, value),
            if (parts.length > _mostParts)
              Text('and ${parts.length - _mostParts} more', style: small),
          ],
        },
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => onSources([
              for (final one in sources)
                if (one != source) one,
            ]),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Take this value away'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: sources.length >= DataSource.maxCount
              ? null
              : () => _add(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a value'),
        ),
      ),
    ]);
  }
}
