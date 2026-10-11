import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/catalogue.dart';
import 'package:openlauncher/editor/inspector.dart';
import 'package:openlauncher/editor/layers.dart';
import 'package:openlauncher/editor/object_tree.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/snapping.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_link.dart';
import 'package:openlauncher/editor/tv_screen.dart';

// The web editor: the launcher itself running in the browser against the TV's
// data (tv_link.dart), plus editing tools. Built by tool/build_editor.sh.

void main() =>
    runApp(ProviderScope(overrides: tvOverrides, child: const EditorApp()));

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenLauncher',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: .fromSeed(seedColor: Colors.indigo, brightness: .dark),
    ),
    home: const EditorScreen(),
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  /// Above this width the side panels sit beside the screen, not under it.
  static const _wide = 1000.0;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

/// The side panels.
enum _Side {
  add('Add', Icons.add),
  objects('Objects', Icons.account_tree_outlined),
  settings('Settings', Icons.tune);

  const _Side(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  bool _editing = true;

  /// The panel shown on the left, and under the screen when narrow.
  _Side _left = _Side.add, _under = _Side.add;

  /// Tabs for [among], showing [shown].
  Widget _sides(
    List<_Side> among,
    _Side shown,
    void Function(_Side side) onChanged, {
    required bool picked,
  }) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: SegmentedButton<_Side>(
          showSelectedIcon: false,
          segments: [
            for (final side in among)
              ButtonSegment(
                value: side,
                icon: Icon(side.icon),
                label: Text(
                  side == _Side.settings && picked ? 'Selected' : side.label,
                ),
              ),
          ],
          selected: {shown},
          onSelectionChanged: (chosen) => onChanged(chosen.single),
        ),
      ),
      Expanded(
        // All kept alive so each keeps its state.
        child: IndexedStack(
          index: among.indexOf(shown),
          sizing: StackFit.expand,
          children: [
            for (final side in among)
              switch (side) {
                _Side.add => const Catalogue(),
                _Side.objects => const ObjectTree(),
                _Side.settings => const Inspector(),
              },
          ],
        ),
      ),
    ],
  );

  /// Keeps the launcher's state across layout changes.
  final _stage = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Selecting something shows its settings.
    ref.listen(selectionProvider.select((ids) => ids.isNotEmpty), (_, picked) {
      if (picked) setState(() => _under = _Side.settings);
    });
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        title: const Text('OpenLauncher'),
        actions: [
          if (_editing) ...const [SnapButton(), LayersButton()],
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.edit_outlined),
                label: Text('Edit'),
                tooltip: 'Move things about and add new ones',
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.tv_outlined),
                label: Text('Use'),
                tooltip: 'Use it as on the TV: arrow keys, Enter, or tap',
              ),
            ],
            selected: {_editing},
            onSelectionChanged: (chosen) {
              ref.read(selectionProvider.notifier).clear();
              setState(() => _editing = chosen.single);
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      // Delete removes the selection; Escape clears it.
      body: CallbackShortcuts(
        bindings: {
          if (_editing) ...{
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                removeSelected(context, ref),
            const SingleActivator(LogicalKeyboardKey.escape): ref
                .read(selectionProvider.notifier)
                .clear,
          },
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= EditorScreen._wide;
            final picked = ref.watch(
              selectionProvider.select((ids) => ids.isNotEmpty),
            );
            final screen = Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: TvScreen.size.aspectRatio,
                  child: FittedBox(
                    child: Stage(key: _stage, editing: _editing),
                  ),
                ),
              ),
            );
            Widget side(Widget child) => Material(color: surface, child: child);
            if (!_editing) return screen;
            return wide
                ? Row(
                    children: [
                      SizedBox(
                        width: 316,
                        child: side(
                          _sides(
                            const [_Side.add, _Side.objects],
                            _left,
                            (side) => setState(() => _left = side),
                            picked: picked,
                          ),
                        ),
                      ),
                      Expanded(child: screen),
                      SizedBox(width: 300, child: side(const Inspector())),
                    ],
                  )
                // When narrow, the panels take turns under the screen.
                : Column(
                    children: [
                      screen,
                      Expanded(
                        child: side(
                          _sides(
                            _Side.values,
                            _under,
                            (side) => setState(() => _under = side),
                            picked: picked,
                          ),
                        ),
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }
}
