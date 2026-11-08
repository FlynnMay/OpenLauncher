import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Answers a source at an address the launcher itself answers: plain values
/// and rows, pictures as file paths. [watch] reads it again when what it
/// reads changes; the live ones always do.
typedef SourceEndpoint = FutureOr<Object?> Function(Ref ref, bool watch);

/// What `os://<area>` (the TV) and `launcher://<area>` (the launcher) answer
/// as sources, by address. Each feature declares its own; the registry puts
/// them together and fills this in where the app starts.
final sourceEndpointsProvider = Provider<Map<String, SourceEndpoint>>(
  (ref) => throw StateError(
    'Source endpoints are not registered: add sourceEndpointOverrides to '
    'the ProviderScope or ProviderContainer.',
  ),
);

/// [provider] watched when [watch], else read once.
T readOrWatch<T>(Ref ref, ProviderListenable<T> provider, bool watch) =>
    watch ? ref.watch(provider) : ref.read(provider);
