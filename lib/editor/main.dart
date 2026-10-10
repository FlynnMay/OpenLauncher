import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/catalogue.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/tv_api.dart';

// The config page as a Flutter web app, served by the TV at /editor/ next
// to the first page (assets/web/index.html), which it is to replace. It
// draws the TV's screen with the TV's own widgets. Built by
// tool/build_editor.sh.

void main() => runApp(const ProviderScope(child: EditorApp()));

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenLauncher',
    debugShowCheckedModeBanner: false,
    // The TV's own theme, so the replica looks the same.
    theme: ThemeData(
      colorScheme: .fromSeed(seedColor: Colors.indigo, brightness: .dark),
    ),
    home: const EditorScreen(),
  );
}

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  /// From this width on, the catalogue is beside the screen, not under it.
  static const _wide = 760.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorProvider);
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        title: const Text('OpenLauncher'),
        actions: [
          IconButton(
            tooltip: 'Ask the TV again',
            onPressed: () => ref.invalidate(editorProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: editor.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not reach the TV: $error'),
          ),
        ),
        data: (state) => LayoutBuilder(
          builder: (context, constraints) {
            final screen = Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: Stage.size.aspectRatio,
                  child: FittedBox(child: Stage(state: state)),
                ),
              ),
            );
            final catalogue = Material(
              color: surface,
              child: Catalogue(state: state),
            );
            return constraints.maxWidth >= _wide
                ? Row(
                    children: [
                      SizedBox(width: 316, child: catalogue),
                      Expanded(child: screen),
                    ],
                  )
                : Column(
                    children: [
                      screen,
                      Expanded(child: catalogue),
                    ],
                  );
          },
        ),
      ),
    );
  }
}
