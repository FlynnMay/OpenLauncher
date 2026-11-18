import 'package:openlauncher_domain/nodes/node_names.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// A root of a template as an address: segments joined by `/`, the first one
/// maybe starting with `pack:`, then `#module` last. Quotes are taken off.
class NodePath {
  const NodePath(this.segments, [this.module]);

  /// An empty segment, as in `a//b`, is left out.
  factory NodePath.parse(String root) {
    final parts = _Parts(root)..read();
    return NodePath(parts.segments, parts.module);
  }

  final List<String> segments;

  final String? module;

  /// The word it starts with when that stands for a place in the tree.
  String? get keyword =>
      segments.isNotEmpty && reservedWords.contains(segments.first)
      ? segments.first
      : null;

  /// The first [count] segments as one id.
  String idOf(int count) => segments.take(count).join('/');

  /// Whether it is one plain id: no children, no module, no keyword.
  bool get isWholeId =>
      segments.length == 1 && module == null && keyword == null;
}

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

class _Parts {
  _Parts(this._text);

  final String _text;
  final segments = <String>[];
  String? module;
  final _current = StringBuffer();
  var _at = 0;

  void read() {
    while (_at < _text.length) {
      final char = _text[_at];
      if (_startsQuote(char)) {
        _quoted(char);
      } else if (char == '/') {
        _endSegment();
        _at++;
      } else if (char == '#') {
        _endSegment();
        module = _text.substring(_at + 1);
        return;
      } else {
        _current.write(char);
        _at++;
      }
    }
    _endSegment();
  }

  bool _startsQuote(String char) =>
      (char == "'" || char == '"') &&
      (_current.isEmpty || _current.toString().endsWith(':'));

  void _quoted(String quote) {
    final close = _text.indexOf(quote, _at + 1);
    final end = close == -1 ? _text.length : close;
    _current.write(_text.substring(_at + 1, end));
    _at = end + 1;
  }

  void _endSegment() {
    if (_current.isNotEmpty) segments.add(_current.toString());
    _current.clear();
  }
}
