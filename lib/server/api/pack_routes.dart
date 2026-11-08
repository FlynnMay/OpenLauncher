import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class PackRoutes implements ApiRoutes {
  PackRoutes(this._ref);

  final Ref _ref;

  PackStore get _store => _ref.read(packStoreProvider);

  @override
  void addTo(Router router) {
    router
      ..get('/api/packs/<packId>/<pathInPack|.*>', _serveFileOfPack)
      ..post('/api/packs', _installPack)
      ..delete('/api/packs', _deletePack)
      // A secret setting is only ever sent this way, and never read back.
      ..put('/api/secret', _setSecret)
      ..delete('/api/secret', _clearSecret);
  }

  /// Checked with the TV each time: a pack can be replaced by one of the same
  /// version.
  Future<Response> _serveFileOfPack(
    Request request,
    String packId,
    String pathInPack,
  ) async => serveFileChecked(
    request,
    await _store.pathOf(packId, pathInPack),
    'No such file',
  );

  Future<Response> _installPack(Request request) async {
    final pack = await _store.install(request.read());
    return jsonResponse({'id': pack.id});
  }

  Future<Response> _deletePack(Request request) async {
    final id = request.url.queryParameters['id'];
    if (id == null) throw const FormatException('"id" must name a pack');
    await _ref.read(packServiceProvider).delete(id);
    return emptyJsonResponse();
  }

  Future<Response> _setSecret(Request request) async {
    final body = await readJsonObject(request);
    await _keepSecret(request, body['value']);
    return emptyJsonResponse();
  }

  Future<Response> _clearSecret(Request request) async {
    await _keepSecret(request, null);
    return emptyJsonResponse();
  }

  Future<void> _keepSecret(Request request, Object? value) {
    final query = request.url.queryParameters;
    return _ref
        .read(packServiceProvider)
        .setSecret(query['pack'], query['key'], value);
  }
}
