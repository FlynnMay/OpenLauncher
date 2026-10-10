import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/cards/launcher_card.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// A widget the TV can show, as the catalogue offers it.
typedef WidgetOffer = ({
  String type,
  String label,
  double w,
  double h,
  Map<String, Object?> options,
});

/// What the TV says there is to show and to choose from.
class TvState {
  const TvState({
    required this.cards,
    required this.config,
    required this.widgets,
    this.wallpaper,
  });

  final List<LauncherCard> cards;

  /// The layout and the pictures of folders, as far as the page knows them.
  final LauncherConfig config;
  final List<WidgetOffer> widgets;

  /// The address of a still wallpaper, if that is what the TV has.
  final String? wallpaper;

  Layout get layout => config.layout;

  TvState withLayout(Layout layout) => TvState(
    cards: cards,
    config: LauncherConfig(layout: layout, iconOverrides: config.iconOverrides),
    widgets: widgets,
    wallpaper: wallpaper,
  );
}

final tvApiProvider = Provider<TvApi>((ref) => TvApi());

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
    final wallpaper = json['wallpaper'] as Map?;
    final providers = json['widgetProviders'] as List;
    return TvState(
      cards: await Future.wait([
        for (final Map card in json['cards'] as List) _card(card),
      ]),
      config: LauncherConfig(
        layout: Layout.fromJson(json['layout'] as Map),
        iconOverrides: {
          for (final MapEntry(:key, :value)
              in (json['panelIcons'] as Map).entries)
            PanelEntry.iconKey(key as String): _at(value as String).toString(),
        },
      ),
      widgets: [
        for (final Map widget in json['widgets'] as List)
          // An app widget is offered once for each one an app provides.
          for (final Map? provider
              in widget['type'] == 'android' ? providers : [null])
            (
              type: widget['type'] as String,
              label: provider == null
                  ? widget['label'] as String
                  : '${provider['app']}: ${provider['label']}',
              w: (widget['w'] as num).toDouble(),
              h: (widget['h'] as num).toDouble(),
              options: {'provider': ?provider?['id']},
            ),
      ],
      wallpaper: wallpaper?['kind'] == 'image'
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

final editorProvider = AsyncNotifierProvider<EditorController, TvState>(
  EditorController.new,
);

/// What the editor shows: the TV's state, with the user's own changes
/// applied the moment they are made.
class EditorController extends AsyncNotifier<TvState> {
  @override
  Future<TvState> build() => ref.watch(tvApiProvider).state();

  /// Shows [layout] at once and sends it to the TV. If the TV does not take
  /// it, what the TV has is shown again and the error is thrown.
  Future<void> setLayout(Layout layout) async {
    final api = ref.read(tvApiProvider);
    // Repaired here the way the TV will repair it, so the two agree.
    state = AsyncData((await future).withLayout(layout.normalised()));
    try {
      await api.setLayout(layout);
    } finally {
      state = await AsyncValue.guard(api.state);
    }
  }
}
