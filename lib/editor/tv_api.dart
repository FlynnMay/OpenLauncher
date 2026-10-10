import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';

/// A widget the TV can show, as the catalogue offers it.
typedef WidgetOffer = ({
  String type,
  String label,
  double w,
  double h,
  Map<String, Object?> options,
});

/// What the TV says it has: the same things the launcher on the TV works
/// from, with every picture as the address the TV serves it at.
class TvState {
  const TvState({
    required this.cards,
    required this.config,
    required this.widgets,
    this.wallpaper,
  });

  /// Every card, with the user's names and pictures already applied.
  final List<LauncherCard> cards;

  /// The layout, the pictures of folders and the options.
  final LauncherConfig config;
  final List<WidgetOffer> widgets;
  final Wallpaper? wallpaper;
}

final tvApiProvider = Provider<TvApi>((ref) => TvApi());

/// What the TV has, and again each time it changes.
final tvStateProvider = StreamProvider<TvState>(
  (ref) => ref.watch(tvApiProvider).states(),
);

/// The TV's config API, at the address this page came from.
class TvApi {
  final _client = http.Client();
  final _base = Uri.base;

  /// Line art by address: the address changes when the drawing does.
  final _drawings = <String, Future<String>>{};

  Uri _at(String path) => _base.resolve(path);

  /// Follows the TV's event stream, joining it again whenever it is lost.
  /// Fails only if the TV cannot be reached to begin with.
  Stream<TvState> states() async* {
    var reached = false;
    while (true) {
      try {
        final response = await _client.send(
          http.Request('GET', _at('/api/events')),
        );
        if (response.statusCode != 200) {
          throw Exception('The TV answered ${response.statusCode}');
        }
        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          yield await _state(jsonDecode(line.substring(6)) as Map);
          reached = true;
        }
      } on Object {
        if (!reached) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<TvState> _state(Map<Object?, Object?> json) async {
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
        contextMenu: [
          for (final name in json['contextMenu'] as List)
            ?CardAction.named(name),
        ],
        toasts: ToastOptions.fromJson(json['toasts'] as Map),
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
      wallpaper: wallpaper == null
          ? null
          : Wallpaper(
              _at(wallpaper['url'] as String).toString(),
              WallpaperKind.values.byName(wallpaper['kind'] as String),
            ),
    );
  }

  Future<LauncherCard> _card(Map<Object?, Object?> json) async {
    final icon = json['icon'] as String?;
    final bare = json['bare'] == true && icon != null;
    return LauncherCard(
      id: json['id'] as String,
      kind: CardKind.values.byName(json['kind'] as String),
      target: json['id'] as String,
      label: json['label'] as String,
      // On the TV this is a file; here it is where the TV serves that file.
      iconPath: bare || icon == null ? null : _at(icon).toString(),
      wideIcon: json['wide'] == true,
      svg: bare
          ? await _drawings.putIfAbsent(
              icon,
              () async => (await _client.get(_at(icon))).body,
            )
          : null,
    );
  }

  Future<void> _put(String path, Object? body) async {
    final response = await _client.put(_at(path), body: jsonEncode(body));
    if (response.statusCode != 200) {
      throw Exception('The TV answered ${response.statusCode}');
    }
  }

  Future<void> setLayout(Layout layout) => _put('/api/layout', layout.toJson());

  Future<void> setOptions(LauncherConfig config) => _put('/api/options', {
    'contextMenu': [for (final action in config.contextMenu) action.name],
    'toasts': config.toasts.toJson(),
  });
}
