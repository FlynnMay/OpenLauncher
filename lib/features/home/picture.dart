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
