import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/cards/launcher_card.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/home/styled_box.dart';

// SPIKE: the config page as a Flutter web app, served by the TV next to the
// old page. It draws the home screen with the TV's own widgets from
// `/api/state`, and moves a card when it is dropped on another, to try
// dragging by mouse and by finger. Not the editor yet.

void main() => runApp(const EditorApp());

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

/// What the TV says there is to show.
class TvState {
  TvState(this.cards, this.config, this.wallpaper);

  final List<LauncherCard> cards;
  final LauncherConfig config;

  /// The address of a still wallpaper, if that is what the TV has.
  final String? wallpaper;
}

/// The TV's config API, at the address this page came from.
class TvApi {
  final _client = http.Client();
  final _base = Uri.base;

  Uri _at(String path) => _base.resolve(path);

  Future<TvState> state() async {
    final response = await _client.get(_at('/api/state'));
    if (response.statusCode != 200) {
      throw Exception('The TV answered ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final cards = await Future.wait([
      for (final Map card in json['cards'] as List) _card(card),
    ]);
    final wallpaper = json['wallpaper'] as Map?;
    return TvState(
      cards,
      LauncherConfig(
        layout: Layout.fromJson(json['layout'] as Map),
        iconOverrides: {
          for (final MapEntry(:key, :value)
              in (json['panelIcons'] as Map).entries)
            PanelEntry.iconKey(key as String): _at(value as String).toString(),
        },
      ),
      wallpaper?['kind'] == 'image'
          ? _at(wallpaper!['url'] as String).toString()
          : null,
    );
  }

  Future<LauncherCard> _card(Map<Object?, Object?> json) async {
    final icon = json['icon'] as String?;
    final bare = json['bare'] == true && icon != null;
    return LauncherCard(
      id: json['id'] as String,
      kind: CardKind.values.byName(json['kind'] as String),
      target: '',
      label: json['label'] as String,
      // On the TV this is a file; here it is where the TV serves that file.
      iconPath: bare || icon == null ? null : _at(icon).toString(),
      wideIcon: json['wide'] == true,
      svg: bare ? (await _client.get(_at(icon))).body : null,
    );
  }

  Future<void> setLayout(Layout layout) async {
    final response = await _client.put(
      _at('/api/layout'),
      body: jsonEncode(layout.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('The TV answered ${response.statusCode}');
    }
  }
}

/// [layout] after the item [moved] was dropped on the item [onto]: in a flow
/// pane it goes in front of it, anywhere else the two change places.
Layout dropOnto(Layout layout, String moved, String onto) {
  LayoutItem? find(String id) {
    for (final panel in layout.panels) {
      for (final pane in panel.root.panes) {
        for (final item in pane.items) {
          if (item.id == id) return item;
        }
      }
    }
    return null;
  }

  LayoutItem at(LayoutItem item, LayoutItem place) =>
      LayoutItem.fromJson({...item.toJson(), 'x': place.x, 'y': place.y});

  final from = find(moved), to = find(onto);
  if (from == null || to == null || moved == onto) return layout;
  return Layout(
    inbox: layout.inbox,
    removed: layout.removed,
    panels: [
      for (final panel in layout.panels)
        panel.withRoot(
          panel.root.rebuild(
            (pane, items) => [
              for (final item in items)
                if (item.id == onto) ...[
                  at(from, to),
                  if (pane.mode != PaneMode.flow && from.x != null)
                    at(to, from)
                  else
                    to,
                ] else if (item.id != moved)
                  item,
            ],
          ),
        ),
    ],
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _api = TvApi();
  TvState? _state;
  String _status = 'Loading…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _api.state();
      setState(() {
        _state = state;
        _status = '${state.cards.length} cards';
      });
    } on Object catch (error) {
      setState(() => _status = 'Could not reach the TV: $error');
    }
  }

  Future<void> _drop(String moved, String onto) async {
    final state = _state!;
    final layout = dropOnto(state.config.layout, moved, onto);
    // Shown at once; the TV's answer follows.
    setState(() {
      _state = TvState(
        state.cards,
        LauncherConfig(
          layout: layout,
          iconOverrides: state.config.iconOverrides,
        ),
        state.wallpaper,
      );
      _status = 'Saving…';
    });
    try {
      await _api.setLayout(layout);
    } on Object catch (error) {
      setState(() => _status = 'Could not save: $error');
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        title: const Text('OpenLauncher (Flutter spike)'),
        actions: [
          Center(child: Text(_status)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  child: Stage(state: state, onDrop: _drop),
                ),
              ),
            ),
    );
  }
}

/// The TV's screen, at the TV's own size.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.state, required this.onDrop});

  final TvState state;
  final void Function(String moved, String onto) onDrop;

  Widget _tile(Entry entry) => switch (entry) {
    PaneEntry(:final view) => PaneBox(view: view, tile: _tile),
    _ => _Movable(
      id: entry.item.id,
      onDrop: onDrop,
      child: switch (entry) {
        CardEntry(:final card) => ArtTile(
          label: card.label,
          art: CardArt(card: card),
          bare: CardArt.isBare(card),
          showLabel: !entry.item.hideName,
          boxStyle: entry.item.style,
          onSelect: () {},
        ),
        PanelEntry() => ArtTile(
          label: entry.label,
          art: FolderArt(entry: entry),
          bare: FolderArt.isBare(entry),
          showLabel: !entry.item.hideName,
          boxStyle: entry.item.style,
          onSelect: () {},
        ),
        _ => StyledBox(
          style: entry.item.style,
          radius: 10,
          padding: const EdgeInsets.all(8),
          child: Center(child: Text(entry.item.ref)),
        ),
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final home = resolveLayout(state.cards, state.config).home.root;
    return Container(
      width: 960,
      height: 540,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: Colors.black),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (state.wallpaper case final wallpaper?)
            Image(image: pictureAt(wallpaper), fit: BoxFit.cover),
          const ColoredBox(color: Color(0x73000000)),
          SingleChildScrollView(
            padding: EdgeInsets.all(home.pane.padding ?? 0),
            child: PaneGrid(view: home, tile: _tile),
          ),
        ],
      ),
    );
  }
}

/// Something that can be picked up and dropped on another of its kind: at
/// once with a mouse, after a hold with a finger, so that a swipe scrolls.
class _Movable extends StatelessWidget {
  const _Movable({required this.id, required this.onDrop, required this.child});

  final String id;
  final void Function(String moved, String onto) onDrop;
  final Widget child;

  static bool get _byFinger =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    // The tile's own taps and holds are the remote's; here they are ours.
    // Absorbed, not ignored: the drag starts where the tile is touched.
    final tile = AbsorbPointer(child: child);
    final feedback = Opacity(
      opacity: 0.8,
      child: SizedBox(width: 140, height: 97, child: tile),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != id,
      onAcceptWithDetails: (details) => onDrop(details.data, id),
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: candidates.isEmpty
              ? null
              : Border.all(color: Colors.lightBlueAccent, width: 2),
        ),
        child: _byFinger
            ? LongPressDraggable<String>(
                data: id,
                delay: const Duration(milliseconds: 280),
                feedback: feedback,
                childWhenDragging: Opacity(opacity: 0.3, child: tile),
                child: tile,
              )
            : Draggable<String>(
                data: id,
                feedback: feedback,
                childWhenDragging: Opacity(opacity: 0.3, child: tile),
                child: tile,
              ),
      ),
    );
  }
}
