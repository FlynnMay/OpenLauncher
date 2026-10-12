import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openlauncher/editor/controls/app_mark_svg.dart';

/// The app's mark, in the colour of the icons around it.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    appMarkSvg,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      IconTheme.of(context).color ?? Colors.white,
      BlendMode.srcIn,
    ),
  );
}
