import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A file on the TV; a URL in the browser.
ImageProvider pictureAt(String source) =>
    kIsWeb ? NetworkImage(source) : FileImage(File(source)) as ImageProvider;

/// SVG markup, or an SVG file on the TV.
Widget svgPicture(String source) => SvgPicture(
  source.startsWith('<') ? SvgStringLoader(source) : _SvgFile(source),
  fit: BoxFit.contain,
);

/// A filled pill holding [text] over the lower right of a 16:9 picture, as
/// SVG to lay over it.
String badgeSvg(String text) {
  const height = 26.0, centreX = 119.0, centreY = 61.0;
  final width = height + (text.length - 1) * 10;
  final said = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90">'
      '<rect x="${centreX - width / 2}" y="${centreY - height / 2}" '
      'width="$width" height="$height" rx="${height / 2}" fill="#fff"/>'
      '<text x="$centreX" y="${centreY + 6}" text-anchor="middle" '
      'font-family="sans-serif" font-size="17" font-weight="700" '
      'fill="#14161c">$said</text></svg>';
}

class _SvgFile extends SvgLoader<void> {
  const _SvgFile(this.path);

  final String path;

  @override
  String provideSvg(void message) =>
      utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);

  @override
  bool operator ==(Object other) => other is _SvgFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
