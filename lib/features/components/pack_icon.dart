import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';

/// An icon from an installed pack, by its saved name (`set:name`). Empty
/// until its set has loaded, and for a name no set has.
class PackIcon extends ConsumerWidget {
  const PackIcon(this.name, {super.key, this.size = 24, this.color});

  final String name;
  final double size;

  /// Null for the text colour around it.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final named = iconRef(name);
    final set = named == null
        ? null
        : ref.watch(iconSetProvider(named.set)).value;
    final code = set?.icons[named?.name]?.code;
    return SizedBox.square(
      dimension: size,
      child: code == null
          ? null
          : Center(
              child: ExcludeSemantics(
                // Drawn as text: a font loaded at run time has no IconData.
                child: Text(
                  String.fromCharCode(code),
                  textDirection: TextDirection.ltr,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    inherit: false,
                    fontFamily: set!.family,
                    fontSize: size,
                    height: 1,
                    color: color ?? DefaultTextStyle.of(context).style.color,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
            ),
    );
  }
}
