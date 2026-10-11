/// A built-in entity that provides data, as the editor lists it: its id,
/// label and fields.
typedef BuiltInValue = ({String root, String label, List<String> parts});

const List<BuiltInValue> builtInValues = [
  (
    root: 'clock',
    label: 'Clock',
    parts: [
      'time',
      'date',
      'hour',
      'minute',
      'second',
      'hour12',
      'ampm',
      'weekday',
      'day',
      'month',
      'monthName',
      'year',
    ],
  ),
  (
    root: 'media',
    label: 'Media Player',
    parts: ['title', 'artist', 'app', 'playing', 'art'],
  ),
  (
    root: 'location',
    label: 'Location',
    parts: ['name', 'latitude', 'longitude'],
  ),
  (
    root: 'weather',
    label: 'Weather',
    parts: ['temperature', 'high', 'low', 'description'],
  ),
];

/// Ids a user value may not take.
final builtInRoots = {for (final value in builtInValues) value.root, 'source'};
