import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/catalogue.dart';
import 'package:openlauncher/editor/inspector.dart';
import 'package:openlauncher/editor/layers.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_link.dart';

// The config page as a Flutter web app, served by the TV at /editor/ next
// to the first page (assets/web/index.html), which it is to replace. It
// runs the launcher itself, fed by the TV over the network (tv_link.dart),
// and adds the means to rearrange it. Built by tool/build_editor.sh.

void main() =>
    runApp(ProviderScope(overrides: tvOverrides, child: const EditorApp()));

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenLauncher',
    debugShowCheckedModeBanner: false,
    // The launcher's own theme.
    theme: ThemeData(
      colorScheme: .fromSeed(seedColor: Colors.indigo, brightness: .dark),
    ),
    home: const EditorScreen(),
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  /// From this width on, the catalogue and the settings of what is picked
  /// out are either side of the screen, not under it.
  static const _wide = 1000.0;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  bool _editing = true;

  /// Keeps the launcher as it was when the page is laid out anew.
  final _stage = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        title: const Text('OpenLauncher'),
        actions: [
          if (_editing) const LayersButton(),
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
      // Delete takes what is picked out off the TV; Escape lets go of it.
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
                      SizedBox(width: 316, child: side(const Catalogue())),
                      Expanded(child: screen),
                      SizedBox(width: 300, child: side(const Inspector())),
                    ],
                  )
                // With less room they take turns under the screen: what
                // can be added, until something is picked out.
                : Column(
                    children: [
                      screen,
                      Expanded(
                        child: side(
                          picked ? const Inspector() : const Catalogue(),
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
