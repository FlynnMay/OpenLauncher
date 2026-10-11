/// The widgets the launcher can show. A layout item of kind `widget` names
/// one of these in its `ref`.
enum WidgetKind {
  clock('Clock', 2, 1),
  weather('Weather', 2, 1),
  media('Now playing', 2, 1),

  /// The three a widget of the user's own is put together from, in a pane:
  /// each shows what its options say, written as templates
  /// (`{{weather.temperature}}`).
  text('Text', 2, 1),
  picture('Picture', 2, 2),
  meter('Meter', 2, 1),

  /// A widget provided by an installed app; the item's `provider` option
  /// says which.
  android('App widget', 2, 2);

  const WidgetKind(this.label, this.defaultW, this.defaultH);

  final String label;

  /// The size, in cells, a new widget of this kind starts with.
  final int defaultW, defaultH;

  /// The options a new widget of this kind starts with.
  Map<String, Object?> get starter => switch (this) {
    text => const {'text': '{{time}}'},
    meter => const {'value': '{{time.second}}', 'max': 60},
    _ => const {},
  };

  static WidgetKind? named(String name) => values.asNameMap()[name];
}
