import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/catalogue.dart';
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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  /// From this width on, the catalogue is beside the screen, not under it.
  static const _wide = 760.0;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
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
            onSelectionChanged: (chosen) =>
                setState(() => _editing = chosen.single),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= EditorScreen._wide;
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
          final catalogue = Material(
            color: surface,
            child: _editing ? const Catalogue() : const SizedBox.shrink(),
          );
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            children: wide
                ? [
                    SizedBox(width: _editing ? 316 : 0, child: catalogue),
                    Expanded(child: screen),
                  ]
                : [screen, Expanded(child: catalogue)],
          );
        },
      ),
    );
  }
}
