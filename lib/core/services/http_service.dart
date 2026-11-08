import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';

/// Overridden in tests.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Requests to the web that a pack's action makes, signed by the pack's auth
/// profile. Only the TV does this, since only it holds the secrets.
class HttpService {
  HttpService(this._ref);

  final Ref _ref;

  static const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  /// The pack an entity belongs to: the part of its id before the colon.
  static String? packOf(String? entityId) =>
      entityId != null && entityId.contains(':')
      ? entityId.substring(0, entityId.indexOf(':'))
      : null;

  /// Sends [method] to [url]. A [body] map goes as JSON, text as it is. With
  /// [auth], the profile of the pack that [entityId] belongs to signs it, if
  /// it is for the profile's host. Throws unless the answer is a 2xx.
  Future<String?> request({
    required String? entityId,
    required String method,
    required String url,
    String? auth,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final address = HttpFeed.addressOf(url);
    if (address == null) throw FormatException('"$url" is not a web address');
    final request = http.Request(method, address)
      ..headers.addAll({
        if (body != null && body is! String) 'content-type': 'application/json',
        ...headers,
        ...await _signature(packOf(entityId), auth, address),
      });
    if (body != null) request.body = body is String ? body : jsonEncode(body);
    final response = await http.Response.fromStream(
      await _ref
          .read(httpClientProvider)
          .send(request)
          .timeout(const Duration(seconds: 15)),
    );
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw http.ClientException('Status ${response.statusCode}', address);
    }
    return null;
  }

  Future<Map<String, String>> _signature(
    String? packId,
    String? auth,
    Uri address,
  ) async {
    if (auth == null || auth.isEmpty) return const {};
    final packs = await _ref.read(packsProvider.future);
    final profile = packs
        .where((pack) => pack.id == packId)
        .firstOrNull
        ?.auth[auth];
    if (profile == null) {
      throw FormatException('${packId ?? 'This'} has no auth "$auth"');
    }
    await _ref.read(configProvider.future);
    final settings = plainSettingsOf(_ref, packId);
    final secrets =
        (await _ref.read(packSecretsProvider.future))[packId] ?? const {};
    return profile.headersFor(address, settings: settings, secrets: secrets) ??
        (throw FormatException('"$auth" will not sign a request to $address'));
  }
}

/// The values the user gave the settings of [packId], secrets left out.
Map<String, Object?> plainSettingsOf(Ref ref, String? packId) =>
    ref.read(configProvider).value?.packSettings[packId] ?? const {};

final httpServiceProvider = Provider<HttpService>(HttpService.new);
