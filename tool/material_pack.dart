// Rebuilds packs/material from Google's Material Symbols: the outlined font
// at one weight, and an index of every icon with its category and search
// words. Run it when Google has added icons: dart run tool/material_pack.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _family = 'Material Symbols Outlined';
const _weight = 300;
const _font = 'material-symbols-outlined.ttf';
const _out = 'packs/material';

Future<void> main() async {
  final client = http.Client();
  try {
    // An old browser is sent TrueType, which is all Flutter reads everywhere.
    final css = await client.get(
      Uri.https('fonts.googleapis.com', '/css2', {
        'family': '$_family:opsz,wght,FILL,GRAD@24,$_weight,0,0',
      }),
      headers: {'user-agent': 'Mozilla/4.0'},
    );
    final url = RegExp(r'url\((https://[^)]+\.ttf)\)').firstMatch(css.body)?[1];
    if (url == null) throw StateError('No font in:\n${css.body}');
    final font = await client.get(Uri.parse(url));
    final version = RegExp(r'/v(\d+)/').firstMatch(url)?[1] ?? '0';

    final reply = await client.get(
      Uri.https('fonts.google.com', '/metadata/icons', {'incomplete': 'true'}),
    );
    // The first line guards against being run as a script.
    final metadata =
        jsonDecode(reply.body.substring(reply.body.indexOf('\n'))) as Map;
    final icons = [
      for (final Map icon in metadata['icons'] as List)
        if (!(icon['unsupported_families'] as List).contains(_family)) icon,
    ]..sort(_mostUsedFirst);
    final categories = {
      for (final icon in icons) ...(icon['categories'] as List).cast<String>(),
    }.toList()..sort();

    await Directory('$_out/fonts').create(recursive: true);
    await Directory('$_out/icons').create(recursive: true);
    await File('$_out/fonts/$_font').writeAsBytes(font.bodyBytes);
    await File('$_out/pack.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'id': 'material', 'name': 'Material Symbols', 'version': version, 'author': 'Google', 'licence': 'Apache-2.0'})}\n',
    );
    await File('$_out/icons/material.json').writeAsString(
      jsonEncode({
        'name': 'Material Symbols',
        'font': _font,
        'categories': [
          for (final category in categories) category.replaceAll('&', ' & '),
        ],
        'icons': {
          for (final icon in icons)
            icon['name']: [
              icon['codepoint'],
              categories.indexOf((icon['categories'] as List).first as String),
              _words(icon),
            ],
        },
      }),
    );
    stdout.writeln(
      '${icons.length} icons in ${categories.length} categories, '
      'font v$version (${font.bodyBytes.length} bytes)',
    );
  } finally {
    client.close();
  }
}

/// The index's order is the order a picker shows.
int _mostUsedFirst(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  final byUse = (b['popularity'] as num).compareTo(a['popularity'] as num);
  return byUse != 0
      ? byUse
      : (a['name'] as String).compareTo(b['name'] as String);
}

/// The words of [icon]'s tags that its name does not already hold.
String _words(Map<Object?, Object?> icon) {
  final named = (icon['name'] as String).split('_').toSet();
  final words = <String>{
    for (final String tag in icon['tags'] as List)
      for (final word in tag.toLowerCase().split(RegExp('[^a-z0-9]+')))
        if (word.length > 1 && word != 'icon' && !named.contains(word)) word,
  };
  return words.join(' ');
}
