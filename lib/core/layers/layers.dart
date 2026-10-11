import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One layer of the screen above the home screen: what has been moved to
/// it is drawn over everything on the layers below, and the layer says
/// what becomes of those while it is there.
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

  /// How much what is below is blurred; 0 for not at all.
  final double blur;

  /// How much what is below is darkened, 0 to 1.
  final double dim;

  /// True for a layer that keeps the focus to itself while it is there:
  /// what is below cannot be reached, and Back takes the layer away.
  final bool modal;

  /// The ids of the components that are on it.
  final Set<String> holds;

  ScreenLayer holding(Set<String> holds) =>
      ScreenLayer(id: id, blur: blur, dim: dim, modal: modal, holds: holds);
}

/// The layers there are above the home screen now, the lowest first. They
/// are made and taken away as the launcher runs, by actions: a sidebar
/// that is revealed makes one and moves to it, unless it is set to do
/// otherwise.
final layersProvider = NotifierProvider<ScreenLayers, List<ScreenLayer>>(
  ScreenLayers.new,
);

class ScreenLayers extends Notifier<List<ScreenLayer>> {
  var _next = 1;

  @override
  List<ScreenLayer> build() => const [];

  /// Puts a new layer over all there are.
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

  /// Moves [component] to the top layer, from whichever it was on. With no
  /// layer above the home screen it stays where it is.
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

  /// Takes away the layer [component] is on, or the top one where it is on
  /// none; what was on it goes back to where it is laid out.
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

/// The id of the layer [component] is on, or null for where it is laid out.
int? layerOf(List<ScreenLayer> layers, String component) =>
    layers.where((layer) => layer.holds.contains(component)).firstOrNull?.id;
