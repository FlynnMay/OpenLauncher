import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/variables/variables.dart';

/// A node drawn over the screen, with what is behind it dimmed or blurred.
@immutable
class OpenOverlay {
  const OpenOverlay(
    this.id, {
    this.dim = 0,
    this.blur = 0,
    this.modal = false,
    this.opener,
  });

  final String id;

  /// 0 to 1.
  final double dim;

  final double blur;

  /// Back closes it, and the focus cannot leave it.
  final bool modal;

  /// What had the focus when it opened; it gets it back on closing.
  final FocusNode? opener;
}

/// The overlays open on the screen, lowest first, in the order they opened.
final overlaysProvider = NotifierProvider<Overlays, List<OpenOverlay>>(
  Overlays.new,
);

class Overlays extends Notifier<List<OpenOverlay>> {
  /// Backdrops asked for by an action, for nodes about to open.
  final _asked = <String, OpenOverlay>{};

  @override
  List<OpenOverlay> build() => const [];

  /// Puts [overlay] on top, moving it there if it is open.
  void open(OpenOverlay overlay) => state = [
    for (final open in state)
      if (open.id != overlay.id) open,
    overlay,
  ];

  /// Opens [id] as an action asked for it, else as [otherwise] if given.
  void opened(String id, [OpenOverlay? otherwise]) {
    if (_asked.remove(id) ?? otherwise case final overlay?) open(overlay);
  }

  /// Has the next [opened] of [overlay]'s node use it.
  void ask(OpenOverlay overlay) => _asked[overlay.id] = overlay;

  /// Takes [id] off, the top one without; a node opened by its `open`
  /// variable has it cleared.
  void close([String? id]) {
    final gone = id ?? state.lastOrNull?.id;
    if (gone == null) return;
    remove(gone);
    final vars = ref.read(runtimeVarsProvider);
    if (vars[gone]?[openVar] == true) {
      ref.read(runtimeVarsProvider.notifier).set(gone, openVar, false);
    }
  }

  /// Closes every one.
  void closeAll() {
    for (final open in [...state.reversed]) {
      close(open.id);
    }
  }

  /// Takes [id] off, leaving its `open` variable.
  void remove(String id) {
    if (state.every((open) => open.id != id)) return;
    state = [
      for (final open in state)
        if (open.id != id) open,
    ];
  }
}
