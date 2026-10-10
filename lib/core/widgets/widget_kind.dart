/// The widgets the launcher can show. A layout item of kind `widget` names
/// one of these in its `ref`.
enum WidgetKind {
  clock('Clock', 2, 1),
  weather('Weather', 2, 1),
  media('Now playing', 2, 1),

  /// A widget provided by an installed app; the item's `provider` option
  /// says which.
  android('App widget', 2, 2);

  const WidgetKind(this.label, this.defaultW, this.defaultH);

  final String label;

  /// The size, in cells, a new widget of this kind starts with.
  final int defaultW, defaultH;

  static WidgetKind? named(String name) => values.asNameMap()[name];
}
