import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/tree_view.dart';

/// Something drawn over the screen while editing, on top of the outlines
/// editing always shows, to make visible what cannot otherwise be seen.
/// Each can be switched on by itself. A new kind of layer is a value here,
/// a line in [layerTree], and what draws it in `LayerStack`
/// (`layer_stack.dart`).
enum EditLayer {
  navUp('Up', Icons.arrow_upward, Color(0xFF8C9EFF)),
  navDown('Down', Icons.arrow_downward, Color(0xFFFF8A80)),
  navLeft('Left', Icons.arrow_back, Color(0xFFFFD54F)),
  navRight('Right', Icons.arrow_forward, Color(0xFF69F0AE));

  const EditLayer(this.label, this.icon, this.colour);

  final String label;
  final IconData icon;

  /// What it is drawn in, to tell it from the others.
  final Color colour;

  /// The way the D-pad is pressed, for a layer that shows where that leads.
  NavDirection? get direction => switch (this) {
    navUp => NavDirection.up,
    navDown => NavDirection.down,
    navLeft => NavDirection.left,
    navRight => NavDirection.right,
  };
}

/// The layers that are switched on.
final layersProvider = NotifierProvider<Layers, Set<EditLayer>>(Layers.new);

class Layers extends Notifier<Set<EditLayer>> {
  @override
  Set<EditLayer> build() => const {};

  void set(Iterable<EditLayer> layers, {required bool shown}) =>
      state = shown ? {...state, ...layers} : state.difference(layers.toSet());
}

TreeNode<EditLayer> _line(EditLayer layer) => TreeNode(
  label: layer.label,
  value: layer,
  trailing: Icon(layer.icon, color: layer.colour, size: 18),
);

/// The layers as they are listed: those that belong together under a
/// heading, which switches them all.
final layerTree = <TreeNode<EditLayer>>[
  TreeNode(
    label: 'Navigation',
    children: [
      _line(EditLayer.navUp),
      _line(EditLayer.navDown),
      _line(EditLayer.navLeft),
      _line(EditLayer.navRight),
    ],
  ),
];

/// The button that lists the layers and switches them on and off.
class LayersButton extends ConsumerWidget {
  const LayersButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(layersProvider);
    return MenuAnchor(
      builder: (context, menu, _) => Badge(
        isLabelVisible: shown.isNotEmpty,
        label: Text('${shown.length}'),
        child: IconButton(
          tooltip: 'Layers: what is drawn over the screen',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.layers_outlined),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 230,
          // Watched here too: the menu is drawn apart from the button.
          child: Consumer(
            builder: (context, ref, _) => TreeView<EditLayer>(
              nodes: layerTree,
              checked: ref.watch(layersProvider),
              onChanged: (layers, checked) =>
                  ref.read(layersProvider.notifier).set(layers, shown: checked),
            ),
          ),
        ),
      ],
    );
  }
}
