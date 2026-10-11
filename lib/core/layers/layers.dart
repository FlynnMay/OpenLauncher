import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A layer above the home screen. What is moved to it is drawn over the
/// layers below.
@immutable
class ScreenLayer {
  const ScreenLayer({
    required this.id,
    this.blur = 0,
    this.dim = 0,
    this.modal = false,
    this.holds = const {},
  });

  final int id;

  /// Blur of what is below; 0 for none.
  final double blur;

  /// Dimming of what is below, 0 to 1.
  final double dim;

  /// Takes the focus; Back closes the layer.
  final bool modal;

  /// Ids of the components on it.
  final Set<String> holds;

  ScreenLayer holding(Set<String> holds) =>
      ScreenLayer(id: id, blur: blur, dim: dim, modal: modal, holds: holds);
}

/// The current layers, lowest first. Runtime only; created and closed by
/// actions.
final layersProvider = NotifierProvider<ScreenLayers, List<ScreenLayer>>(
  ScreenLayers.new,
);

class ScreenLayers extends Notifier<List<ScreenLayer>> {
  var _next = 1;

  @override
  List<ScreenLayer> build() => const [];

  /// Adds a layer on top.
  void create({double blur = 0, double dim = 0, bool modal = false}) =>
      state = [
        ...state,
        ScreenLayer(
          id: _next++,
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

/// The layer holding [component], or null.
int? layerOf(List<ScreenLayer> layers, String component) =>
    layers.where((layer) => layer.holds.contains(component)).firstOrNull?.id;
