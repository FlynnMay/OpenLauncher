import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/auth_store.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:shelf/shelf.dart';

final authProvider = Provider<Authenticator>(
  (ref) => Authenticator(ref.watch(authStoreProvider)),
);

/// Why a request was turned down, as an HTTP status.
class AuthRefused implements Exception {
  const AuthRefused(this.status, this.message);

  final int status;
  final String message;
}

/// Guards the web API: a browser pairs with the TV using the 6-digit code the
/// TV shows (by typing it, or by scanning the QR, which carries it), and is
/// then given a token it sends on every later request. The token is a long
/// random string kept only as its hash, so the stored list cannot be
/// replayed. Requests whose `Host` is not the TV's own address are refused,
/// which stops a remote site reaching the API by DNS rebinding.
class Authenticator {
  Authenticator(this._store) {
    _rotate();
  }

  final AuthStore _store;
  final _random = Random.secure();
  final _code = ValueNotifier<String>('000000');

  /// After this many wrong tries the code is rotated.
  static const _maxFails = 5;

  /// A device's last-seen time is only rewritten this far apart, to spare a
  /// disk write on every request.
  static const _touchEvery = Duration(minutes: 5);

  int _fails = 0;
  List<TrustedDevice>? _devices;
  Future<void>? _loading;

  /// The pairing code the TV shows; changes on each pair and after too many
  /// wrong tries.
  String get code => _code.value;

  /// For a widget that shows the code live.
  ValueListenable<String> get codeListenable => _code;

  void _rotate() {
    _code.value = _random.nextInt(1000000).toString().padLeft(6, '0');
    _fails = 0;
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async => _devices = [...await _store.load()];

  /// [base] with the code in the fragment, which browsers do not send to the
  /// server, so it stays out of logs.
  Uri pairingUri(Uri base) => base.replace(fragment: 'pair=${_code.value}');

  /// Lets a request through (null) or blocks it. The editor's own files and
  /// `POST /api/pair` need no token; everything else does.
  Future<Response?> guard(Request request) async {
    if (!await _hostAllowed(request)) {
      return _refuse(403, 'This address is not the TV.');
    }
    final path = request.url.path;
    if (EditorFiles.owns(path)) return null;
    if (request.method == 'POST' && path == 'api/pair') return null;
    final token =
        _bearer(request) ?? request.url.queryParameters['t'];
    if (token == null || !await _verify(token)) {
      return _refuse(401, 'This device is not paired with the TV.');
    }
    return null;
  }

  /// Checks [code] and, if it matches, trusts a new device called [label] and
  /// returns its `token` and `device`. The code is rotated whether or not it
  /// matched, so it is good for one pairing only.
  Future<Map<String, Object?>> pair(String code, String label) async {
    await _ensureLoaded();
    if (!_sameCode(code.trim(), _code.value)) {
      _fails++;
      if (_fails >= _maxFails) _rotate();
      throw const AuthRefused(401, 'That code is not right. Check the TV.');
    }
    final token = _token();
    final now = DateTime.now();
    final device = TrustedDevice(
      id: _id(),
      tokenHash: _hash(token),
      label: label.trim().isEmpty ? 'A device' : label.trim(),
      added: now,
      lastSeen: now,
    );
    _devices!.add(device);
    await _store.save(_devices!);
    _rotate();
    return {'token': token, 'device': device.forEditor()};
  }

  /// The trusted devices, newest first, without their token hashes.
  Future<List<Map<String, Object?>>> devices() async {
    await _ensureLoaded();
    return [
      for (final device in _devices!.reversed) device.forEditor(),
    ];
  }

  /// Stops trusting device [id].
  Future<void> revoke(String id) async {
    await _ensureLoaded();
    _devices!.removeWhere((device) => device.id == id);
    await _store.save(_devices!);
  }

  Future<bool> _verify(String token) async {
    await _ensureLoaded();
    final hash = _hash(token);
    final at = _devices!.indexWhere((d) => _sameCode(d.tokenHash, hash));
    if (at < 0) return false;
    final now = DateTime.now();
    if (now.difference(_devices![at].lastSeen) > _touchEvery) {
      _devices![at] = _devices![at].seenAt(now);
      unawaited(_store.save(_devices!).catchError((Object _) {}));
    }
    return true;
  }

  Set<String>? _hosts;

  Future<bool> _hostAllowed(Request request) async {
    // Built from the Host header by the server, so this still refuses a name
    // a remote site rebinds to the TV's address.
    final host = request.requestedUri.host;
    if (host.isEmpty) return false;
    if ((_hosts ??= await _ownHosts()).contains(host)) return true;
    // An address may have changed since the list was built; refresh once.
    return (_hosts = await _ownHosts()).contains(host);
  }

  Future<Set<String>> _ownHosts() async {
    final hosts = {'localhost', '127.0.0.1', '::1'};
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final address in interface.addresses) {
          hosts.add(address.address);
        }
      }
    } on Object catch (e) {
      debugPrint('Could not list network addresses: $e');
    }
    return hosts;
  }

  Response _refuse(int status, String message) =>
      Response(status, body: jsonEncode({'error': message}), headers: const {
        'content-type': 'application/json; charset=utf-8',
      });

  static String? _bearer(Request request) {
    final header = request.headers['authorization'];
    if (header == null) return null;
    const prefix = 'Bearer ';
    return header.startsWith(prefix) ? header.substring(prefix.length) : null;
  }

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  String _token() => _bytes(32);
  String _id() => _bytes(9);

  String _bytes(int count) => base64Url
      .encode(List<int>.generate(count, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  /// Compares two equal-purpose strings without leaking how far they match.
  static bool _sameCode(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
