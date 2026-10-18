import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/variables/variables.dart';

/// Nodes drawn over the screen, and the popup an action fired in.
class OverlayOperationsManager implements OperationsManager {
  OverlayOperationsManager(this._ref);

  final Ref _ref;

  Overlays get _overlays => _ref.read(overlaysProvider.notifier);

  /// The node [id] names on the screen shown.
  Node? _find(String id) => _ref.read(currentScreenProvider)?.find(id);

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'launcher://overlay/open',
      label: 'Open a node over the screen',
      // `of` is a node id, empty for the one it fired from; `dim` a
      // percentage. Unset, they are the node's Overlay's.
      args: const {
        'of': [],
        'dim': [],
        'blur': [],
        'modal': ['true', 'false'],
      },
      run: (run) async {
        final id = run.arg('of') ?? run.component;
        final node = id == null ? null : _find(id);
        if (node == null) {
          debugPrint('overlay/open: no node "$id" on this screen');
          return null;
        }
        double? asked(String key) =>
            run.args.containsKey(key) ? run.number(key) : null;
        final overlay = OpenOverlay(
          node.id,
          dim: switch (asked('dim')) {
            final dim? => dim.clamp(0, 100) / 100,
            null => node.overlayDim,
          },
          blur: (asked('blur') ?? node.overlayBlur)
              .clamp(0, OverlayModule.maxBlur)
              .toDouble(),
          modal: run.flag('modal', otherwise: node.overlayModal),
          opener: FocusManager.instance.primaryFocus,
        );
        if (node.isDocked || node.isOverlay) {
          // Opened by its `open` variable, which the host turns into this.
          _overlays.ask(overlay);
          _ref.read(runtimeVarsProvider.notifier).set(node.id, openVar, true);
        } else {
          _overlays.open(overlay);
        }
        return null;
      },
    ),
    Operation(
      name: 'launcher://overlay/close',
      label: 'Close a node over the screen',
      // `of` is a node id; empty, the overlay it fired in, else the top one.
      args: const {'of': []},
      run: (run) async {
        final of = run.arg('of');
        _overlays.close(
          of == null ? _around(run.component) : _find(of)?.id ?? of,
        );
        return null;
      },
    ),
    Operation(
      name: 'launcher://popups/close',
      label: 'Close the popup it fired in',
      run: (run) async {
        run.screen?.close();
        return null;
      },
    ),
  ];

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
