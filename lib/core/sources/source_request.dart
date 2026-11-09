import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/values/template.dart';

/// Said when a pack's source cannot be fetched yet, and why.
class SourceNotReady implements Exception {
  const SourceNotReady(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The fetch a web source in [at] asks for: its address and body filled from
/// its pack's settings, and signed by its auth profile. Throws
/// [SourceNotReady] while a required setting of the pack has no value.
Future<HttpFeed> requestOf(Ref ref, SourceAt at, {bool reactive = true}) async {
  final T Function<T>(ProviderListenable<T>) read = reactive
      ? ref.watch
      : ref.read;
  final source = at.source;
  final pack = await _packOf(ref, read, source);
  // Waits for the config without rebuilding on every edit of it.
  await ref.read(configProvider.future);
  final settings = read(
    configProvider.select(
      (config) => config.value?.packSettings[source.pack] ?? const {},
    ),
  );
  final secrets = pack == null
      ? const <String, String>{}
      : (await read(packSecretsProvider.future))[pack.id] ?? const {};
  if (pack != null) _requireSettings(pack, settings, secrets);
  final address = HttpFeed.addressOf(_fill(source.address, settings));
  if (address == null) {
    throw SourceNotReady('"${source.address}" is not a web address yet');
  }
  return HttpFeed(
    at.id,
    address,
    source.every ?? 60,
    method: source.method,
    headers: _signature(pack, source, address, settings, secrets),
    body: _bodyOf(source, settings),
  );
}

Future<Pack?> _packOf(
  Ref ref,
  T Function<T>(ProviderListenable<T>) read,
  Source source,
) async {
  if (source.pack == null) return null;
  final packs = await read(packsProvider.future);
  return packs.where((pack) => pack.id == source.pack).firstOrNull;
}

void _requireSettings(
  Pack pack,
  Map<String, Object?> settings,
  Map<String, String> secrets,
) {
  for (final setting in pack.settings) {
    final value = setting.secret ? secrets[setting.key] : settings[setting.key];
    if (setting.required && '${value ?? ''}'.isEmpty) {
      throw SourceNotReady('${pack.name} needs "${setting.label}"');
    }
  }
}

/// Only plain settings are read here; a secret is never put in an address or
/// a body.
String _fill(String text, Map<String, Object?> settings) =>
    Template.parse(text).render((root) => root == 'settings' ? settings : null);

Map<String, String> _signature(
  Pack? pack,
  Source source,
  Uri address,
  Map<String, Object?> settings,
  Map<String, String> secrets,
) {
  final name = source.auth;
  if (name == null) return const {};
  final headers = pack?.auth[name]?.headersFor(
    address,
    settings: settings,
    secrets: secrets,
  );
  if (headers == null) {
    throw SourceNotReady('"$name" will not sign a request to $address');
  }
  return headers;
}

String? _bodyOf(Source source, Map<String, Object?> settings) =>
    switch (source.body) {
      null => null,
      final String text => _fill(text, settings),
      final map => _fill(jsonEncode(map), settings),
    };

/// Fetches source [name] of pack [packId] again, now, for whatever shows its
/// rows. Nothing if the pack has no such source.
Future<void> fetchSourceAgain(Ref ref, String packId, String name) async {
  final contents = await ref.read(packContentsProvider.future);
  final source = contents
      .where((one) => one.pack.id == packId)
      .firstOrNull
      ?.sources[name];
  if (source == null || source.answeredHere) return;
  final feed = await requestOf(ref, (
    id: '$packId:$name',
    source: source,
  ), reactive: false);
  ref.invalidate(feedValueProvider(feed));
}
