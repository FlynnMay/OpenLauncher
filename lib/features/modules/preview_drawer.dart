import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/modules/visual_look.dart';

/// A small picture of another node and what is in it.
///
/// Values: `node` (a template that reads as the node's id).
class PreviewVisual extends ConsumerWidget {
  const PreviewVisual({super.key, required this.values});

  /// Its module's values, with its style under `style`.
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      NodeArt(node: visualText(context, ref, values['node']).trim());
}
