import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/media/media_dirs.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The pictures and wallpapers the user uploaded.
class MediaRoutes implements ApiRoutes {
  MediaRoutes(this._ref);

  final Ref _ref;

  MediaStore get _store => _ref.read(mediaStoreProvider);

  @override
  void addTo(Router router) {
    router
      ..get('/api/media/<fileId>', _serveUploadedFile)
      ..get('/api/media', _listUploadedFiles)
      ..post('/api/media', _keepUploadedFile)
      ..delete('/api/media', _deleteOneOrAllUnusedFiles);
  }

  Future<Response> _serveUploadedFile(Request request, String fileId) async =>
      serveImmutableFile(request, await _store.pathOf(fileId), 'No such file');

  Future<Response> _listUploadedFiles(Request request) async => jsonResponse({
    'files': [
      for (final file in await _store.list())
        {'id': file.id, 'bytes': file.bytes, 'used': file.used},
    ],
  });

  /// Keeps the file in the body for `as` (a `picture` or a `wallpaper`) and
  /// answers its `{id}`.
  Future<Response> _keepUploadedFile(Request request) async {
    final use = MediaUse.values.asNameMap()[request.url.queryParameters['as']];
    if (use == null) {
      throw const FormatException('"as" must be picture or wallpaper');
    }
    final id = await _store.add(request.read(), use);
    return jsonResponse({'id': id});
  }

  /// Without an id, every file nothing points at.
  Future<Response> _deleteOneOrAllUnusedFiles(Request request) async {
    final id = request.url.queryParameters['id'];
    if (id == null) {
      return jsonResponse({'deleted': await _store.deleteUnused()});
    }
    await _store.delete(id);
    return emptyJsonResponse();
  }
}
