import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/services/command_service.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The layout, the settings kept beside it, and the place lookup for the
/// weather.
class ConfigRoutes implements ApiRoutes {
  ConfigRoutes(this._ref);

  final Ref _ref;

  @override
  void addTo(Router router) {
    router
      ..put('/api/layout', _replaceLayout)
      ..delete('/api/layout', _resetLayoutToStarting)
      ..put('/api/config', _setSettings)
      ..get('/api/geocode', _findPlacesNamed);
  }

  Future<Response> _replaceLayout(Request request) async {
    final body = await readJsonObject(request);
    await _ref.read(configProvider.notifier).setLayout(Layout.fromJson(body));
    return emptyJsonResponse();
  }

  Future<Response> _resetLayoutToStarting(Request request) => revisionResponse(
    _ref
        .read(commandsProvider)
        .run(const ResetLayoutToStarting(), session: editingSessionOf(request)),
  );

  /// Sets the config keys in the body; files are named by id. Unreadable
  /// values fall back to defaults instead of failing.
  Future<Response> _setSettings(Request request) async {
    final body = await readJsonObject(request);
    if (LauncherConfig.settingsValidationError(body) case final reason?) {
      throw FormatException(reason);
    }
    await _ref
        .read(configProvider.notifier)
        .patch(await _ref.read(mediaStoreProvider).withPaths(body));
    return emptyJsonResponse();
  }

  /// Geocoding for the weather, proxied so the page only talks to the TV.
  Future<Response> _findPlacesNamed(Request request) async {
    final query = request.url.queryParameters['q'];
    if (query == null || query.trim().isEmpty) {
      throw const FormatException('"q" must name a place');
    }
    try {
      final places = await findPlaces(
        _ref.read(jsonFetcherProvider),
        query.trim(),
      );
      return jsonResponse({
        'places': [
          for (final place in places)
            {
              'name': place.name,
              'latitude': place.latitude,
              'longitude': place.longitude,
            },
        ],
      });
    } on Exception catch (e) {
      return errorResponse(502, 'The TV could not look that up: $e');
    }
  }
}
