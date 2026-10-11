/// An entity the launcher has of its own that provides data: the id a
/// template names it by, what it is called, and the parts it has beside
/// how it reads whole. What each is at the time is its kind's to say, in
/// `entity_kinds.dart`; this is what the editor lists them from.
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

/// The names a value of the user's may not take: the launcher's own
/// entities, and `source`, which is what an instance is drawn from.
final builtInRoots = {for (final value in builtInValues) value.root, 'source'};
