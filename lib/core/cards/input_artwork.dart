import 'package:openlauncher/platform/launcher_platform.dart';

/// Draws the picture for an input card as SVG: a white line drawing on a
/// transparent background, used as-is by the TV and by the config page.
///
/// A trailing number in [label] ("HDMI 2") becomes a badge over the corner.
String inputArtworkSvg(TvInputKind kind, String label) {
  final shape = switch (kind) {
    // The outline of an HDMI socket, with its contact bar.
    TvInputKind.hdmi =>
      '<path d="M42 26h76a4 4 0 0 1 4 4v15l-13 15H51L38 45V30a4 4 0 0 1 4-4z"/>'
          '<path d="M56 40h48"/>',
    // A television with a rabbit-ear aerial.
    TvInputKind.tuner =>
      '<rect x="46" y="36" width="68" height="38" rx="5"/>'
          '<path d="M80 36 66 16M80 36l14-20"/>',
    // Three phono sockets.
    TvInputKind.analog =>
      [52, 80, 108]
          .map(
            (x) =>
                '<circle cx="$x" cy="45" r="10"/>'
                '<circle cx="$x" cy="45" r="1.5"/>',
          )
          .join(),
    // A signal going into a box.
    TvInputKind.other =>
      '<rect x="50" y="24" width="60" height="42" rx="5"/>'
          '<path d="M80 34v22m-8-8 8 8 8-8"/>',
  };
  final number = RegExp(r'(\d+)\s*$').firstMatch(label)?[1];
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
      'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '$shape${number == null ? '' : _badge(number)}'
      '</svg>';
}

/// A filled pill holding [text], overlapping the drawing's lower right corner.
/// One digit makes it a circle.
String _badge(String text) {
  const height = 26.0, centreX = 119.0, centreY = 61.0;
  final width = height + (text.length - 1) * 10;
  return '<rect x="${centreX - width / 2}" y="${centreY - height / 2}" '
      'width="$width" height="$height" rx="${height / 2}" '
      'fill="#fff" stroke="none"/>'
      '<text x="$centreX" y="${centreY + 6}" text-anchor="middle" '
      'font-family="sans-serif" font-size="17" font-weight="700" '
      'fill="#14161c" stroke="none">$text</text>';
}
