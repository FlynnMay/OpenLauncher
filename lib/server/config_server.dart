import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/config_api.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The running web server, or null if it could not start.
final configServerProvider = FutureProvider<ConfigServer?>((ref) async {
  final api = ref.watch(configApiProvider);
  // A fixed port keeps bookmarks working; the next few are fallbacks.
  for (
    var port = ConfigServer.preferredPort;
    port < ConfigServer.preferredPort + 10;
    port++
  ) {
    try {
      final server = await shelf_io.serve(
        api.handle,
        InternetAddress.anyIPv4,
        port,
      );
      ref.onDispose(() => server.close(force: true));
      return ConfigServer(server.port);
    } on SocketException catch (e) {
      debugPrint('Config server: port $port unavailable: $e');
    }
  }
  return null;
});

class ConfigServer {
  ConfigServer(this.port);

  static const preferredPort = 8080;

  final int port;

  /// The LAN address, or null with no network. Looked up each call.
  Future<Uri?> url() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return Uri(scheme: 'http', host: address.address, port: port);
        }
      }
    }
    return null;
  }
}
