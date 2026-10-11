/// A value the launcher has of its own: the root a template names it by,
/// what it is, and the parts it has beside how it reads whole.
typedef BuiltInValue = ({String root, String label, List<String> parts});

/// The values every launcher has, whatever the user defined.
const List<BuiltInValue> builtInValues = [
  (
    root: 'time',
    label: 'Time',
    parts: ['hour', 'minute', 'second', 'hour12', 'ampm'],
  ),
  (
    root: 'date',
    label: 'Date',
    parts: ['weekday', 'day', 'month', 'monthName', 'year'],
  ),
  (
    root: 'nowPlaying',
    label: 'Now playing',
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

/// The roots a source of the user's may not be called.
final builtInRoots = {for (final value in builtInValues) value.root};
