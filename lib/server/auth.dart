import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/auth_store.dart';
import 'package:shelf/shelf.dart';

final authProvider = Provider<Authenticator>(
  (ref) => Authenticator(ref.watch(authStoreProvider)),
);

/// The code the TV shows for pairing.
final pairingProvider = Provider<PairingCode>(
  (ref) => ref.watch(authProvider).pairing,
);

/// What became of a pairing attempt.
enum PairAttempt { paired, wrong, closed, locked }

/// A pairing attempt that did not pair, and why.
class PairRefused implements Exception {
  const PairRefused(this.why);

  final PairAttempt why;
}

/// The 6-digit code a browser trades for a session. It exists only while the
/// TV shows it ([open] to [close]), is good for one pairing, and too many
/// wrong tries lock pairing for a while, doubling each time.
class PairingCode {
  PairingCode({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _maxFails = 5;
  static const _firstLock = Duration(seconds: 30);
  static const _longestLock = Duration(minutes: 15);

  final DateTime Function() _clock;
  final _random = Random.secure();
  final _code = ValueNotifier<String?>(null);
  int _fails = 0;
  int _locks = 0;
  DateTime? _lockedUntil;

  /// The code on show, or null while pairing is closed.
  String? get value => _code.value;

  /// For a widget that shows the code live.
  ValueListenable<String?> get listenable => _code;

  /// How long pairing stays locked; zero when it is not.
  Duration get lockedFor {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Opens pairing with a fresh code, for as long as the TV shows it.
  void open() => _rotate();

  void close() => _code.value = null;

  /// [base] with the code in the fragment, which browsers do not send to the
  /// server, so it stays out of logs.
  Uri link(Uri base) => base.replace(fragment: 'pair=${_code.value}');

  /// Checks [code]; a match rotates it so it pairs only once.
  PairAttempt take(String code) {
    final current = _code.value;
    if (current == null) return PairAttempt.closed;
    if (lockedFor > Duration.zero) return PairAttempt.locked;
    if (!_same(code.trim(), current)) {
      if (++_fails >= _maxFails) _lock();
      return PairAttempt.wrong;
    }
    _locks = 0;
    _rotate();
    return PairAttempt.paired;
  }

  void _lock() {
    final lock = _firstLock * (1 << _locks.clamp(0, 10));
    _lockedUntil = _clock().add(lock > _longestLock ? _longestLock : lock);
    _locks++;
    _rotate();
  }

  void _rotate() {
    _code.value = _random.nextInt(1000000).toString().padLeft(6, '0');
    _fails = 0;
  }
}

/// Guards the web API with two middlewares: [hostCheck] for every request
/// and [sessions] for the API.
///
/// A browser pairs by posting the TV's code to `api/pair` and is given a
/// session cookie (`HttpOnly`, `SameSite=Strict`), kept on the TV only as its
/// hash. Writes must also carry [writeHeader] and, if the browser sends one,
/// an `Origin` that is the TV, so no other site can make them.
class Authenticator {
  Authenticator(this._store, {DateTime Function()? clock})
    : pairing = PairingCode(clock: clock);

  final AuthStore _store;
  final PairingCode pairing;
  final _random = Random.secure();
  final _revoked = StreamController<String>.broadcast();

  static const cookie = 'openlauncher_session';

  /// A header another site's page cannot add without the TV agreeing to it
  /// first (a CORS preflight, which the TV never answers).
  static const writeHeader = 'x-requested-with';

  /// Browsers cap cookies at 400 days.
  static const _cookieAge = Duration(days: 400);

  /// A device's last-seen time is only rewritten this far apart, to spare a
  /// disk write on every request.
  static const _touchEvery = Duration(minutes: 5);

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  List<TrustedDevice>? _devices;
  Future<void>? _loading;
  Set<String>? _hosts;

  /// Refuses a request whose `Host` is not one of the TV's addresses, which
  /// stops a remote site reaching the TV by DNS rebinding.
  Middleware get hostCheck =>
      (inner) =>
          (request) async => await _hostAllowed(request)
          ? inner(request)
          : _refuse(403, 'This address is not the TV.');

  /// Pairs, lists and revokes devices, and lets through only requests with a
  /// trusted session. A revoked device's open event streams are closed.
  Middleware get sessions =>
      (inner) => (request) async {
        if (!_safe(request.method) && !_fromEditor(request)) {
          return _refuse(403, 'Changes must come from the editor.');
        }
        final route = (request.method, request.url.path);
        try {
          if (route == ('POST', 'api/pair')) return await _pair(request);
          final device = await _deviceOf(request);
          if (device == null) {
            return _refuse(
              401,
              'This device is not paired with the TV.',
              cookie: _clearCookie,
            );
          }
          return switch (route) {
            ('GET', 'api/devices') => Response.ok(
              jsonEncode({'devices': await devices()}),
              headers: _json,
            ),
            ('DELETE', 'api/devices') => await _revoke(request),
            _ => _closedOnRevoke(await inner(request), device.id),
          };
        } on FormatException catch (e) {
          return _refuse(400, e.message);
        }
      };

  /// The trusted devices, newest first, without their token hashes.
  Future<List<Map<String, Object?>>> devices() async {
    await _ensureLoaded();
    return [for (final device in _devices!.reversed) device.forEditor()];
  }

  /// Trusts a new device called [label] if [code] is the pairing code, and
  /// returns its session token; throws [PairRefused] otherwise.
  Future<({String token, TrustedDevice device})> pair(
    String code,
    String label,
  ) async {
    await _ensureLoaded();
    final attempt = pairing.take(code);
    if (attempt != PairAttempt.paired) throw PairRefused(attempt);
    final token = _bytes(32);
    final now = DateTime.now();
    final device = TrustedDevice(
      id: _bytes(9),
      tokenHash: _hash(token),
      label: label.trim().isEmpty ? 'A device' : label.trim(),
      added: now,
      lastSeen: now,
    );
    _devices!.add(device);
    await _store.save(_devices!);
    return (token: token, device: device);
  }

  /// Stops trusting device [id] and closes its open streams.
  Future<void> revoke(String id) async {
    await _ensureLoaded();
    _devices!.removeWhere((device) => device.id == id);
    await _store.save(_devices!);
    _revoked.add(id);
  }

  Future<Response> _pair(Request request) async {
    final body = jsonDecode(await request.readAsString());
    if (body is! Map) throw const FormatException('Expected a JSON object');
    final ({String token, TrustedDevice device}) paired;
    try {
      paired = await pair('${body['code'] ?? ''}', '${body['label'] ?? ''}');
    } on PairRefused catch (e) {
      final wait = pairing.lockedFor.inSeconds + 1;
      return switch (e.why) {
        PairAttempt.locked => _refuse(
          429,
          'Too many wrong codes. Try again in $wait seconds.',
          retryAfter: wait,
        ),
        PairAttempt.closed => _refuse(
          403,
          'Pairing is closed. On the TV, open "Customise from your phone".',
        ),
        _ => _refuse(403, 'That code is not right. Check the TV.'),
      };
    }
    return Response.ok(
      jsonEncode({'device': paired.device.forEditor()}),
      headers: {
        ..._json,
        'set-cookie':
            '$cookie=${paired.token}; Path=/; HttpOnly; SameSite=Strict; '
            'Max-Age=${_cookieAge.inSeconds}',
      },
    );
  }

  Future<Response> _revoke(Request request) async {
    final id = request.url.queryParameters['id'];
    if (id == null) throw const FormatException('"id" must name a device');
    await revoke(id);
    return Response.ok('{}', headers: _json);
  }

  Future<TrustedDevice?> _deviceOf(Request request) async {
    final token = _cookieOf(request);
    if (token == null) return null;
    await _ensureLoaded();
    final hash = _hash(token);
    final at = _devices!.indexWhere((d) => _same(d.tokenHash, hash));
    if (at < 0) return null;
    final now = DateTime.now();
    if (now.difference(_devices![at].lastSeen) > _touchEvery) {
      _devices![at] = _devices![at].seenAt(now);
      unawaited(_store.save(_devices!).catchError((Object _) {}));
    }
    return _devices![at];
  }

  /// An event stream ends when its device is revoked; other responses are
  /// short and left alone.
  Response _closedOnRevoke(Response response, String id) {
    if (!(response.mimeType?.startsWith('text/event-stream') ?? false)) {
      return response;
    }
    final body = response.read();
    StreamSubscription<List<int>>? reading;
    StreamSubscription<String>? watching;
    late final StreamController<List<int>> out;
    Future<void> stop() async {
      await watching?.cancel();
      await reading?.cancel();
      await out.close();
    }

    out = StreamController<List<int>>(
      onListen: () {
        watching = _revoked.stream.where((r) => r == id).listen((_) => stop());
        reading = body.listen(out.add, onError: out.addError, onDone: stop);
      },
      onCancel: () async {
        await watching?.cancel();
        await reading?.cancel();
      },
    );
    return response.change(body: out.stream);
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async => _devices = [...await _store.load()];

  static bool _safe(String method) =>
      method == 'GET' || method == 'HEAD' || method == 'OPTIONS';

  static bool _fromEditor(Request request) {
    if (request.headers[writeHeader] == null) return false;
    final origin = request.headers['origin'];
    if (origin == null) return true;
    try {
      return Uri.parse(origin).origin == request.requestedUri.origin;
    } on Object {
      // "null" and other origins without a scheme.
      return false;
    }
  }

  static String? _cookieOf(Request request) {
    for (final pair in (request.headers['cookie'] ?? '').split(';')) {
      final at = pair.indexOf('=');
      if (at > 0 && pair.substring(0, at).trim() == cookie) {
        return pair.substring(at + 1).trim();
      }
    }
    return null;
  }

  static const _clearCookie =
      '$cookie=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0';

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

  static Response _refuse(
    int status,
    String message, {
    String? cookie,
    int? retryAfter,
  }) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: {
      ..._json,
      'set-cookie': ?cookie,
      if (retryAfter != null) 'retry-after': '$retryAfter',
    },
  );

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  String _bytes(int count) => base64Url
      .encode(List<int>.generate(count, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
}

/// Compares two strings without leaking how far they match.
bool _same(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
