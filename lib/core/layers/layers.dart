import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layer.dart';

/// The layers made while running, lowest first, above the saved ones.
/// Created and closed by actions.
final layersProvider = NotifierProvider<ScreenLayers, List<Layer>>(
  ScreenLayers.new,
);

class ScreenLayers extends Notifier<List<Layer>> {
  var _next = 1;

  @override
  List<Layer> build() => const [];

  /// Adds a layer on top.
  void create({double blur = 0, double dim = 0, bool modal = false}) =>
      state = [
        ...state,
        Layer.empty(
          'layer-${_next++}',
          blur: blur.clamp(0, 40).toDouble(),
          dim: dim.clamp(0, 1).toDouble(),
          modal: modal,
        ),
      ];

  /// Moves [component] to the top layer. No-op without layers.
  void moveToTop(String component) {
    if (state.isEmpty) return;
    state = [
      for (final layer in state)
        layer.holding({
          ...layer.holds.where((id) => id != component),
          if (layer == state.last) component,
        }),
    ];
  }

  /// Closes the layer holding [component], or the top one.
  void close([String? component]) {
    if (state.isEmpty) return;
    final gone = state.lastWhere(
      (layer) => layer.holds.contains(component),
      orElse: () => state.last,
    );
    state = [
      for (final layer in state)
        if (layer != gone) layer,
    ];
  }
}

/// The layer [component] was moved to, or null.
String? layerOf(List<Layer> layers, String component) =>
    layers.where((layer) => layer.holds.contains(component)).firstOrNull?.id;
