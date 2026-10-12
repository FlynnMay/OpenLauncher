import 'package:flutter/foundation.dart';

/// One icon of a set: its place in the font, its category (an index into
/// [IconSet.categories], -1 for none) and the words it is found by.
typedef Glyph = ({int code, int category, String words});

/// The name an icon is saved by: `set:name`.
typedef IconRef = ({String set, String name});

/// A font of icons with its index, from a pack's `icons/<id>.json`:
/// `{name, font, categories: [..], icons: {name: [codepoint, category,
/// "search words"]}}`.
@immutable
class IconSet {
  const IconSet({
    required this.id,
    required this.name,
    required this.font,
    required this.icons,
    this.categories = const [],
    this.family = '',
  });

  final String id, name;

  /// A file in the pack's `fonts/`.
  final String font;

  final List<String> categories;

  /// In the order a picker shows them.
  final Map<String, Glyph> icons;

  /// The family [font] was loaded as; empty until it is.
  final String family;

  static IconSet? fromJson(String id, Object? json) {
    if (json case {
      'font': final String font,
      'icons': final Map<Object?, Object?> icons,
    }) {
      return IconSet(
        id: id,
        name: switch (json['name']) {
          final String name when name.isNotEmpty => name,
          _ => id,
        },
        font: font,
        categories: [
          if (json['categories'] case final List<Object?> categories)
            for (final category in categories) '$category',
        ],
        icons: {
          for (final MapEntry(key: name, value: glyph) in icons.entries)
            if (name is String)
              if (glyph case [final int code, ...final rest])
                name: (
                  code: code,
                  category: switch (rest) {
                    [final int category, ...] => category,
                    _ => -1,
                  },
                  words: switch (rest) {
                    [_, final String words, ...] => words,
                    _ => '',
                  },
                ),
        },
      );
    }
    return null;
  }

  IconSet loadedAs(String family) => IconSet(
    id: id,
    name: name,
    font: font,
    icons: icons,
    categories: categories,
    family: family,
  );

  /// The saved name of [icon].
  String ref(String icon) => '$id:$icon';

  /// Icon names matching every word of [query], in [category] if given;
  /// those matching by name come first.
  List<String> search(String query, {int? category}) {
    final terms = query
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final named = <String>[], described = <String>[];
    for (final MapEntry(key: name, value: glyph) in icons.entries) {
      if (category != null && glyph.category != category) continue;
      if (terms.every(name.contains)) {
        named.add(name);
      } else if (terms.every(
        (term) => name.contains(term) || glyph.words.contains(term),
      )) {
        described.add(name);
      }
    }
    return named..addAll(described);
  }
}

/// [value] as an icon's saved name; null if it is not one.
IconRef? iconRef(Object? value) {
  if (value is! String) return null;
  final at = value.indexOf(':');
  if (at <= 0 || at == value.length - 1) return null;
  return (set: value.substring(0, at), name: value.substring(at + 1));
}
