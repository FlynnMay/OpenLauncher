import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/packs/pack_contents.dart';
import 'package:openlauncher/core/sources/asked_source_id.dart';
import 'package:openlauncher/core/sources/pack_settings_of.dart';
import 'package:openlauncher/core/sources/sources.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// What the TV knows about its entities: pictures, feed values, actions, and
/// what is playing.
class EntityRoutes implements ApiRoutes {
  EntityRoutes(this._ref);

  final Ref _ref;

  @override
  void addTo(Router router) {
    router
      ..get('/api/icon', _entityPicture)
      ..get('/api/playing/art', _nowPlayingCover)
      ..get('/api/feed', _feedValueFetchedByTv)
      ..post('/api/act', _runAct);
  }

  Future<Response> _entityPicture(Request request) async {
    final entity = await _existingEntity(request);
    if (entity == null) return errorResponse(404, 'Unknown entity');
    final path = entity.data[Entity.icon] as String?;
    // Line art may be SVG markup rather than a file.
    if (path != null &&
        path.startsWith('<') &&
        entity.data[Entity.shape] == Entity.lineArt) {
      return svgResponse(path);
    }
    return serveImmutableFile(request, path, 'No icon');
  }

  /// Serves the cover of what is playing, if the id still names it.
  Future<Response> _nowPlayingCover(Request request) async {
    final id = request.url.queryParameters['id'];
    final path = (await _ref.read(nowPlayingProvider.future))?.artPath;
    return serveImmutableFile(
      request,
      path == null || p.basename(path) != id ? null : path,
      'No cover',
    );
  }

  /// What the feed `id` reads, fetched by the TV because the page cannot
  /// make cross-site requests. `id` is an entity's, or a pack source asked
  /// with arguments (see [AskedSourceId]).
  Future<Response> _feedValueFetchedByTv(Request request) async {
    final id = request.url.queryParameters['id'];
    final at = await (id == null ? null : _feedOf(id));
    // Only the web's: the editor reads the rest itself.
    if (at == null || at.source.answeredHere) {
      return errorResponse(404, 'No such feed');
    }
    // Reuse the value if the TV already shows it; otherwise wait for one.
    final provider = sourceValueProvider(at);
    final held = _ref.listen(provider, (_, _) {});
    try {
      final value = await _ref.read(provider.future);
      return jsonResponse({'value': value});
    } on Exception catch (e) {
      return errorResponse(502, 'The TV could not get that: $e');
    } finally {
      held.close();
    }
  }

  Future<SourceAt?> _feedOf(String id) async {
    final asked = AskedSourceId.parse(id);
    return asked == null ? _entitiesFeed(id) : _askedFeed(asked);
  }

  Future<SourceAt?> _entitiesFeed(String id) async {
    final entities = await _ref.read(entitiesProvider.future);
    final entity = entities.byId(id);
    return entity?.feed?.at(entity.id);
  }

  /// The pack source asked as [asked] says. Only what the source declares is
  /// filled, so the page cannot choose the address.
  Future<SourceAt?> _askedFeed(AskedSourceId asked) async {
    final contents = await _ref.read(packContentsProvider.future);
    final source = contents
        .where((one) => one.pack.id == asked.pack)
        .firstOrNull
        ?.sources[asked.source];
    final settings = _ref.read(packSettingsOfProvider)[asked.pack] ?? const {};
    final request = source?.askedWith(asked.args, settings)?.request;
    return request == null ? null : (id: asked.text, source: request);
  }

  /// Runs the action in the body and answers `{message}`; 400 if it names no
  /// entity that can do it. There is no screen, so screen-only actions do
  /// nothing.
  Future<Response> _runAct(Request request) async {
    final act = Act.fromJson(await readJsonObject(request));
    if (act == null) {
      throw const FormatException(
        '"do" must name an action, or "run" an address',
      );
    }
    try {
      final message = await _ref.read(actionRunnerProvider).run(act);
      return jsonResponse({'message': message});
    } on ImproperAct {
      rethrow;
    } on Exception catch (e) {
      return errorResponse(502, 'The TV could not do that: $e');
    }
  }

  Future<Entity?> _existingEntity(Request request) async {
    final id = request.url.queryParameters['id'];
    final entities = await _ref.read(entitiesProvider.future);
    return id == null ? null : entities.byId(id);
  }
}
