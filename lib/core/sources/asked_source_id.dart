import 'dart:convert';

/// What a pack source asked with arguments is known by: `pack:source#{...}`,
/// the arguments as JSON. The same arguments are the same id, so cards that
/// ask alike share one fetch, and the page can name the request to the TV.
class AskedSourceId {
  const AskedSourceId(this.pack, this.source, this.args);

  final String pack, source;
  final Map<String, Object?> args;

  /// Null if [text] is not written this way.
  static AskedSourceId? parse(String text) {
    final hash = text.indexOf('#');
    final name = hash < 0
        ? const <String>[]
        : text.substring(0, hash).split(':');
    if (name.length != 2) return null;
    try {
      return switch (jsonDecode(text.substring(hash + 1))) {
        final Map<String, Object?> args => AskedSourceId(
          name[0],
          name[1],
          args,
        ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  String get text => '$pack:$source#${jsonEncode(args)}';
}
