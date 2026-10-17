import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/features/components/pack_icon.dart';
import 'package:openlauncher/features/modules/visual_look.dart';

/// An icon from a pack; a value can say which, as the weather says the
/// sky's.
///
/// Values: `icon` (a template that reads as a pack icon's name,
/// `set:name`), `size` (none to fill the box). Look: `color`.
class IconVisual extends ConsumerWidget {
  const IconVisual({super.key, required this.values});

  /// Its module's values, with its style under `style`.
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = visualText(context, ref, values['icon']).trim();
    final size = values['size'];
    final colour = cssColour(visualStyle(context, ref, values)['color']);
    return size is num
        ? PackIcon(icon, color: colour, size: size.toDouble())
        : FittedBox(child: PackIcon(icon, color: colour));
  }
}
