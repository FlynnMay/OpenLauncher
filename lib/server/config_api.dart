import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/api/command_routes.dart';
import 'package:openlauncher/server/api/config_routes.dart';
import 'package:openlauncher/server/api/entity_routes.dart';
import 'package:openlauncher/server/api/media_routes.dart';
import 'package:openlauncher/server/api/pack_routes.dart';
import 'package:openlauncher/server/api/state_routes.dart';
import 'package:openlauncher/server/auth.dart';
import 'package:openlauncher/server/config_page_state.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final configApiProvider = Provider<ConfigApi>((ref) {
  final api = ConfigApi(ref);
  ref.listen(configPageStateProvider, (_, next) {
    if (next case AsyncData(:final value)) api._statePublisher.publish(value);
  }, fireImmediately: true);
  ref.onDispose(api._statePublisher.close);
  return api;
});

/// The HTTP API for the web editor. It uses the same providers and controller
/// as the TV UI; each group of endpoints lives in its own `ApiRoutes`.
class ConfigApi {
  ConfigApi(this._ref);

  final Ref _ref;
  final _statePublisher = StatePublisher();

  Future<Response> handle(Request request) async => _handler(request);

  late final Router _router = () {
    final router = Router(
      notFoundHandler: (_) => errorResponse(404, 'Not found'),
    );
    for (final routes in <ApiRoutes>[
      StateRoutes(_ref, _statePublisher),
      ConfigRoutes(_ref),
      CommandRoutes(_ref),
      EntityRoutes(_ref),
      MediaRoutes(_ref),
      PackRoutes(_ref),
    ]) {
      routes.addTo(router);
    }
    return router;
  }();

  late final Handler _handler = () {
    final auth = _ref.read(authProvider);
    final api = const Pipeline()
        .addMiddleware(auth.sessions)
        .addHandler(_routeAndReportRefusals);
    return const Pipeline()
        .addMiddleware(auth.hostCheck)
        .addHandler(
          (request) =>
              request.method == 'GET' && EditorFiles.owns(request.url.path)
              ? EditorFiles.serve(request)
              : api(request),
        );
  }();

  Future<Response> _routeAndReportRefusals(Request request) async {
    try {
      return await _router.call(request);
    } on FormatException catch (e) {
      return errorResponse(400, e.message);
    } on MediaRefused catch (e) {
      return errorResponse(e.status, e.message);
    } on PackRefused catch (e) {
      return errorResponse(e.status, e.message);
    } on CommandRefused catch (e) {
      return errorResponse(409, e.message);
    }
  }
}
