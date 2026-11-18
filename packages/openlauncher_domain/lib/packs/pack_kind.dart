/// What a pack's JSON file holds.
enum PackKind {
  entity({'id'}),
  field({'extends', 'type', 'label'}),
  source({'url'}),
  generator({'from'}),
  prefab({'id'}),
  screen({'id'});

  const PackKind(this.ownKeys);

  /// The keys only a single object of this kind has. A file without any of
  /// them holds several, each under its name.
  final Set<String> ownKeys;
}
