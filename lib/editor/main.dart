import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/panels/panels.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';

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

/// A key left to a text field while one has the focus.
class _OutsideText extends SingleActivator {
  const _OutsideText(super.trigger, {super.control, super.shift, super.meta});

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      super.accepts(event, state) &&
      primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() ==
          null;
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
    // A prefab deleted from under the editor closes.
    ref.listen(editedPrefabProvider, (was, now) {
      if (was != null && now == null) {
        backPrefab(ref, ref.read(prefabTrailProvider).length - 1);
      }
    });
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    // Where the toolbar has no room for the two labels.
    final roomy = MediaQuery.sizeOf(context).width >= EditorScreen._wide;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        title: const Row(
          spacing: 10,
          children: [
            AppMark(),
            Flexible(child: Text('OpenLauncher')),
          ],
        ),
        actions: [
          if (_editing)
            IconButtonTheme(
              data: IconButtonThemeData(
                style: roomy
                    ? null
                    : IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HistoryButtons(),
                  SnapButton(),
                  LayersButton(),
                  MediaButton(),
                ],
              ),
            ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.edit_outlined),
                label: roomy ? const Text('Edit') : null,
                tooltip: 'Move things about and add new ones',
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.tv_outlined),
                label: roomy ? const Text('Use') : null,
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
            const _OutsideText(LogicalKeyboardKey.delete): () =>
                removeSelected(context, ref),
            for (final (key, shift, back) in const [
              (LogicalKeyboardKey.keyZ, false, true),
              (LogicalKeyboardKey.keyZ, true, false),
              (LogicalKeyboardKey.keyY, false, false),
            ]) ...{
              _OutsideText(key, control: true, shift: shift): () =>
                  stepHistory(context, ref, back: back),
              // Command on a Mac.
              _OutsideText(key, meta: true, shift: shift): () =>
                  stepHistory(context, ref, back: back),
            },
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
            final stage = Padding(
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
            // With the open prefab's bar over it.
            final screen = Column(
              children: [
                const PrefabBar(),
                Expanded(child: stage),
              ],
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
                      const PrefabBar(),
                      stage,
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
