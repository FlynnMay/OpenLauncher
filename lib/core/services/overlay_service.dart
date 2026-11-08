import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/variables/variables.dart';

/// Nodes drawn over the screen.
class OverlayService {
  OverlayService(this._ref);

  final Ref _ref;

  /// Opens the node [id] names on the screen shown. [dim] is a percentage;
  /// what is not given is the node's Overlay's.
  Future<String?> open({
    required String? id,
    double? dim,
    double? blur,
    bool? modal,
  }) async {
    final node = id == null ? null : _find(id);
    if (node == null) {
      debugPrint('overlay/open: no node "$id" on this screen');
      return null;
    }
    final overlay = OpenOverlay(
      node.id,
      dim: dim == null ? node.overlayDim : dim.clamp(0, 100) / 100,
      blur: (blur ?? node.overlayBlur)
          .clamp(0, OverlayModule.maxBlur)
          .toDouble(),
      modal: modal ?? node.overlayModal,
      opener: FocusManager.instance.primaryFocus,
    );
    if (node.isDocked || node.isOverlay) {
      _askHost(node, overlay);
    } else {
      _overlays.open(overlay);
    }
    return null;
  }

  /// Closes the overlay [id] names; none, the one [component] is in, else the
  /// top one.
  Future<String?> close({String? id, String? component}) async {
    closeOverlay(id == null ? _around(component) : _find(id)?.id ?? id);
    return null;
  }

  /// Closes the overlay [id] names, else the top one. A node opened by its
  /// `open` variable has it cleared, so it stays closed.
  void closeOverlay([String? id]) {
    final gone = id ?? _ref.read(overlaysProvider).lastOrNull?.id;
    if (gone == null) return;
    _overlays.remove(gone);
    if (_ref.read(runtimeVarsProvider)[gone]?[openVar] == true) {
      _ref.read(runtimeVarsProvider.notifier).set(gone, openVar, false);
    }
  }

  void closeAll() {
    for (final open in [..._ref.read(overlaysProvider).reversed]) {
      closeOverlay(open.id);
    }
  }

  Overlays get _overlays => _ref.read(overlaysProvider.notifier);

  /// The node [id] names on the screen shown.
  Node? _find(String id) => _ref.read(currentScreenProvider)?.find(id);

  /// Opened by its `open` variable, which the host turns into the overlay.
  void _askHost(Node node, OpenOverlay overlay) {
    _overlays.ask(overlay);
    _ref.read(runtimeVarsProvider.notifier).set(node.id, openVar, true);
  }

  /// The open overlay holding [component], if any.
  String? _around(String? component) {
    if (component == null) return null;
    for (final open in _ref.read(overlaysProvider).reversed) {
      if (_find(open.id)?.all.any((node) => node.id == component) ?? false) {
        return open.id;
      }
    }
    return null;
  }
}

final overlayServiceProvider = Provider<OverlayService>(OverlayService.new);
