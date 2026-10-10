/// A quick action offered when a card is held down. The user chooses which
/// ones appear, and in what order.
enum CardAction {
  open('Open'),
  info('App info'),
  forceStop('Force stop'),
  uninstall('Uninstall'),
  remove('Remove');

  const CardAction(this.label);

  final String label;

  /// The action called [name]; knows the names older configs used.
  static CardAction? named(Object? name) =>
      values.asNameMap()[name == 'hide' ? 'remove' : name];

  /// Whether the action only makes sense for an installed app.
  bool get appOnly => switch (this) {
    info || forceStop || uninstall => true,
    open || remove => false,
  };
}
