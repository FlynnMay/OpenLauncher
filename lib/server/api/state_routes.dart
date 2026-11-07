import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/config_page_state.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Holds the newest page state and tells everyone listening when it changes.
class StatePublisher {
  final _states = StreamController<String>.broadcast();
  String? _latestEncodedState;

  void publish(Map<String, Object?> state) {
    final encoded = jsonEncode(state);
    if (encoded == _latestEncodedState) return;
    _latestEncodedState = encoded;
    _states.add(encoded);
  }

  void close() => _states.close();

  /// Server-sent events: the current state, then every later state.
  Response serverSentEventsResponse() {
    late final StreamController<List<int>> out;
    StreamSubscription<String>? states;
    Timer? keepAlive;
    void send(String text) => out.add(utf8.encode(text));
    out = StreamController(
      onListen: () {
        if (_latestEncodedState case final state?) send('data: $state\n\n');
        states = _states.stream.listen((state) => send('data: $state\n\n'));
        // Comment lines keep idle connections from being dropped.
        keepAlive = Timer.periodic(
          const Duration(seconds: 20),
          (_) => send(': keep-alive\n\n'),
        );
      },
      onCancel: () {
        keepAlive?.cancel();
        return states?.cancel();
      },
    );
    return Response.ok(
      out.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }
}

class StateRoutes implements ApiRoutes {
  StateRoutes(this._ref, this._publisher);

  final Ref _ref;
  final StatePublisher _publisher;

  @override
  void addTo(Router router) {
    router
      ..get('/api/state', _readPageState)
      ..get(
        '/api/events',
        (Request _) => _publisher.serverSentEventsResponse(),
      );
  }

  Future<Response> _readPageState(Request request) async =>
      jsonResponse(await _ref.read(configPageStateProvider.future));
}
