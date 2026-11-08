import 'dart:convert';
import 'dart:io';

import 'package:openlauncher/server/auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

/// A group of related endpoints of the editor's API.
abstract interface class ApiRoutes {
  void addTo(Router router);
}

const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

const _cachedForGood = {'cache-control': 'public, max-age=31536000, immutable'};

Response jsonResponse(Object? body) =>
    Response.ok(jsonEncode(body), headers: jsonHeaders);

Response emptyJsonResponse() => Response.ok('{}', headers: jsonHeaders);

Response errorResponse(int status, String message) => Response(
  status,
  body: jsonEncode({'error': message}),
  headers: jsonHeaders,
);

Future<Map<String, Object?>> readJsonObject(Request request) async {
  final decoded = jsonDecode(await request.readAsString());
  if (decoded is Map<String, Object?>) return decoded;
  throw const FormatException('Expected a JSON object');
}

Future<Response> revisionResponse(Future<int> revisionAfterChange) async =>
    jsonResponse({'revision': await revisionAfterChange});

/// Undo is per device: the one that paired is who is editing.
String editingSessionOf(Request request) =>
    request.context[Authenticator.deviceKey] as String? ?? 'editor';

/// Serves a versioned, immutable file with byte ranges (browsers need them
/// for video).
Future<Response> serveImmutableFile(
  Request request,
  String? path,
  String missingMessage,
) async {
  final response = await _serveExistingFile(request, path, missingMessage);
  return response.statusCode == 404
      ? response
      : response.change(headers: _cachedForGood);
}

/// Serves a file that can be replaced, so a browser asks again every time.
Future<Response> serveFileChecked(
  Request request,
  String? path,
  String missingMessage,
) async {
  final response = await _serveExistingFile(request, path, missingMessage);
  return response.statusCode == 404
      ? response
      : response.change(headers: const {'cache-control': 'no-cache'});
}

Future<Response> _serveExistingFile(
  Request request,
  String? path,
  String missingMessage,
) async {
  if (path == null || !await File(path).exists()) {
    return errorResponse(404, missingMessage);
  }
  return createFileHandler(path, url: request.url.path)(request);
}

Response svgResponse(String markup) => Response.ok(
  markup,
  headers: {..._cachedForGood, 'content-type': 'image/svg+xml'},
);
