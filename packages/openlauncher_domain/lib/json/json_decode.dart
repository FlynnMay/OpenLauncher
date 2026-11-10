/// The one way JSON text is read. Deliberately not in any barrel.
library;

import 'dart:convert';

/// What a piece of JSON text may contain.
enum JsonMode {
  /// Plain JSON.
  strict,

  /// Plain JSON with `//` and `/* */` comments and trailing commas.
  jsonc;

  /// The mode a file name asks for: `.jsonc` is lenient, anything else is
  /// strict.
  static JsonMode ofPath(String path) =>
      path.endsWith('.jsonc') ? jsonc : strict;
}

/// Text that is not JSON, saying which [source] it came from and where.
class JsonDecodeError extends FormatException {
  JsonDecodeError(
    String reason, {
    String? source,
    this.line,
    this.column,
  }) : file = source,
       super(_message(reason, source, line, column));

  /// The file or other place the text was read from.
  final String? file;

  /// 1 based, when the position is known.
  final int? line;
  final int? column;

  static String _message(String reason, String? source, int? line, int? column) {
    final where = [?source, if (line != null) '$line:$column'].join(':');
    return where.isEmpty ? reason : '$where: $reason';
  }
}

/// [text] as JSON. [mode] is what [source] asks for by its extension unless
/// it is given; with neither it is strict. Throws a [JsonDecodeError].
Object? decodeJson(String text, {String? source, JsonMode? mode}) {
  final reading = mode ?? (source == null ? .strict : JsonMode.ofPath(source));
  final cleaned = reading == .jsonc ? _withoutComments(text, source) : text;
  try {
    return jsonDecode(cleaned);
  } on FormatException catch (error) {
    final (:line, :column) = _positionOf(text, error.offset);
    throw JsonDecodeError(
      error.message,
      source: source,
      line: line,
      column: column,
    );
  }
}

({int? line, int? column}) _positionOf(String text, int? offset) {
  if (offset == null || offset < 0 || offset > text.length) {
    return (line: null, column: null);
  }
  final before = text.substring(0, offset);
  final line = '\n'.allMatches(before).length + 1;
  return (line: line, column: offset - before.lastIndexOf('\n'));
}

/// [text] with comments and trailing commas turned into spaces, so every
/// other character keeps its position.
String _withoutComments(String text, String? source) {
  final out = StringBuffer();
  var inString = false;
  var at = 0;
  while (at < text.length) {
    final char = text[at];
    final next = at + 1 < text.length ? text[at + 1] : '';
    if (inString) {
      out.write(char);
      if (char == r'\') {
        out.write(next);
        at += 2;
        continue;
      }
      if (char == '"') inString = false;
      at++;
    } else if (char == '"') {
      inString = true;
      out.write(char);
      at++;
    } else if (char == '/' && next == '/') {
      at = _blankUntil(text, at, '\n', out, keepEnd: true, source: source);
    } else if (char == '/' && next == '*') {
      at = _blankUntil(text, at + 2, '*/', out, prefix: 2, source: source);
    } else {
      out.write(char);
      at++;
    }
  }
  return _withoutTrailingCommas(out.toString());
}

/// Blanks from [from] up to [end], writing spaces (and the new lines) to
/// [out]; returns where reading goes on. A line comment may run to the end of
/// the text; a block comment may not.
int _blankUntil(
  String text,
  int from,
  String end,
  StringBuffer out, {
  required String? source,
  bool keepEnd = false,
  int prefix = 0,
}) {
  final found = text.indexOf(end, from);
  if (found < 0 && !keepEnd) {
    final (:line, :column) = _positionOf(text, from - prefix);
    throw JsonDecodeError(
      'A /* comment is never closed',
      source: source,
      line: line,
      column: column,
    );
  }
  final stop = found < 0 ? text.length : found + (keepEnd ? 0 : end.length);
  final begin = from - prefix;
  out.write(text.substring(begin, stop).replaceAll(RegExp('[^\n]'), ' '));
  return stop;
}

String _withoutTrailingCommas(String text) {
  final out = StringBuffer();
  var inString = false;
  for (var at = 0; at < text.length; at++) {
    final char = text[at];
    if (inString) {
      out.write(char);
      if (char == r'\' && at + 1 < text.length) out.write(text[++at]);
      if (char == '"') inString = false;
    } else if (char == '"') {
      inString = true;
      out.write(char);
    } else if (char == ',' && _closesNext(text, at + 1)) {
      out.write(' ');
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

bool _closesNext(String text, int from) {
  var at = from;
  while (at < text.length && text[at].trim().isEmpty) {
    at++;
  }
  return at < text.length && (text[at] == '}' || text[at] == ']');
}

/// Whether [path] names a JSON or JSONC file.
bool isJsonPath(String path) =>
    path.endsWith('.json') || path.endsWith('.jsonc');

/// [path] without its `.json` or `.jsonc`.
String withoutJsonExtension(String path) =>
    path.endsWith('.jsonc')
    ? path.substring(0, path.length - '.jsonc'.length)
    : path.endsWith('.json')
    ? path.substring(0, path.length - '.json'.length)
    : path;
