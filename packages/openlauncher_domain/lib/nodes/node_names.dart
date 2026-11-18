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
