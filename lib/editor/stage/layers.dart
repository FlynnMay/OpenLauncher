import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// A debug overlay drawn over the screen while editing. A new one is a value
/// here, an entry in [layerTree] and its painter in `layer_stack.dart`.
enum EditLayer {
  navUp('Up', Icons.arrow_upward, Color(0xFF8C9EFF)),
  navDown('Down', Icons.arrow_downward, Color(0xFFFF8A80)),
  navLeft('Left', Icons.arrow_back, Color(0xFFFFD54F)),
  navRight('Right', Icons.arrow_forward, Color(0xFF69F0AE));

  const EditLayer(this.label, this.icon, this.colour);

  final String label;
  final IconData icon;

  final Color colour;

  /// The D-pad direction a navigation overlay shows.
  NavDirection? get direction => switch (this) {
    navUp => NavDirection.up,
    navDown => NavDirection.down,
    navLeft => NavDirection.left,
    navRight => NavDirection.right,
  };
}

/// The enabled overlays.
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

/// The overlays as listed; a heading toggles its group.
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
          // The menu is built outside the button, so it watches too.
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
