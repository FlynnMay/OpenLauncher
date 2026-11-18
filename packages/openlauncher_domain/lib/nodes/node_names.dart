/// Words that start an address and stand for a place in the tree: the node
/// reading, the node holding it, and the root it belongs to. A bare id or
/// variable name may not be one of them.
const reservedWords = {'self', 'parent', 'root'};

final _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

/// Whether [id] can name a node: letters, digits, `_` and `-`. A `.` would
/// read as a variable, a `/` as a child, a `#` as a module, a `:` as a pack.
bool isNodeId(String id) => _id.hasMatch(id);

/// Whether [name] can be given to a bare id or a variable.
bool isFreeName(String name) => !reservedWords.contains(name);

/// [segment] as an address writes it: a plain name as it is, anything else in
/// quotes. Null when it holds both kinds of quote and cannot be written.
String? addressSegment(String segment) => switch (segment) {
  _ when isNodeId(segment) => segment,
  _ when !segment.contains("'") => "'$segment'",
  _ when !segment.contains('"') => '"$segment"',
  _ => null,
};

/// The node [id], `pack:name` or a bare name, as an address writes it. Null
/// when it cannot be written.
String? addressForId(String id) {
  final at = id.indexOf(':');
  if (at < 0) return addressSegment(id);
  final node = addressSegment(id.substring(at + 1));
  return node == null ? null : '${id.substring(0, at + 1)}$node';
}
