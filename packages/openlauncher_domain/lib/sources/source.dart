import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';
import 'package:openlauncher_domain/values/template.dart';

/// Where values come from, from a pack's `sources/<name>.json` or written in
/// place as an entity's feed: `{url, every, watch, rows, method, auth, body}`.
/// `url` is `http(s)://...`, `os://<area>` (the TV) or `launcher://<area>`;
/// in a pack the web's may be a template over `settings`, such as
/// `{{settings.host}}/api/states`.
@immutable
class Source {
  const Source(
    this.address, {
    this.every,
    this.watch = false,
    this.rows = '',
    this.method = 'GET',
    this.auth,
    this.body,
    this.pack,
  });

  static const methods = ['GET', 'POST'];

  /// The text of the address; a template when it holds `{{`.
  final String address;

  /// Seconds between reads; null reads once, or on change if [watch].
  final int? every;

  /// Read again when the source says it changed (not the web's).
  final bool watch;

  /// Path to the list in the answer, e.g. `result.items`; empty for the
  /// answer itself.
  final String rows;

  /// The web's only: one of [methods].
  final String method;

  /// The web's only: the pack's auth profile that signs the request.
  final String? auth;

  /// The web's only: text sent as it is, or a map sent as JSON; may be a
  /// template over `settings`.
  final Object? body;

  /// The pack whose settings fill the templates; set when the pack is read.
  final String? pack;

  /// Whether the launcher answers it rather than the web.
  bool get answeredHere =>
      address.startsWith('os://') || address.startsWith('launcher://');

  bool get isTemplate => address.contains('{{');

  /// The address up to its area, e.g. `os://apps`: what answers it here.
  String get endpoint {
    final url = Uri.parse(address);
    return '${url.scheme}://${url.host}';
  }

  Source inPack(String packId) => Source(
    address,
    every: every,
    watch: watch,
    rows: rows,
    method: method,
    auth: auth,
    body: body,
    pack: packId,
  );

  static Source? fromJson(Object? json) {
    if (json case {'url': final String text}) {
      final address = text.trim();
      final url = Uri.tryParse(address);
      final template = address.startsWith('{{');
      if (!template &&
          (url == null ||
              !((url.isScheme('os') || url.isScheme('launcher')) &&
                      url.host.isNotEmpty ||
                  HttpFeed.addressOf(text) != null))) {
        return null;
      }
      final method = '${json['method'] ?? 'GET'}'.toUpperCase();
      if (!methods.contains(method)) return null;
      return Source(
        address,
        every: switch (json['every']) {
          final num every => every.toInt().clamp(
            HttpFeed.minEvery,
            HttpFeed.maxEvery,
          ),
          _ => null,
        },
        watch: json['watch'] == true,
        rows: switch (json['rows']) {
          final String rows => rows.trim(),
          _ => '',
        },
        method: method,
        auth: switch (json['auth']) {
          final String auth when auth.isNotEmpty => auth,
          _ => null,
        },
        body: switch (json['body']) {
          final String body => body,
          final Map<Object?, Object?> body => jsonStringKeyed(body),
          _ => null,
        },
        pack: switch (json['pack']) {
          final String pack when pack.isNotEmpty => pack,
          _ => null,
        },
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'url': address,
    'every': ?every,
    if (watch) 'watch': true,
    if (rows.isNotEmpty) 'rows': rows,
    if (method != 'GET') 'method': method,
    'auth': ?auth,
    'body': ?body,
    'pack': ?pack,
  };

  /// The rows in [answer]: the list at [rows], or what is there as one row.
  List<Object?> rowsOf(Object? answer) {
    final found = rows.isEmpty
        ? answer
        : Template.parse('{{answer.$rows}}').evaluate((_) => answer);
    return switch (found) {
      null => const [],
      final List<Object?> rows => rows,
      final one => [one],
    };
  }

  @override
  bool operator ==(Object other) =>
      other is Source &&
      other.address == address &&
      other.every == every &&
      other.watch == watch &&
      other.rows == rows &&
      other.method == method &&
      other.auth == auth &&
      other.pack == pack &&
      jsonEncode(other.body) == jsonEncode(body);

  @override
  int get hashCode =>
      Object.hash(address, every, watch, rows, method, auth, pack);
}

/// A source, and what its fetch is known by: `<pack>:<name>` for a pack's,
/// so every reader shares one, else the entity it feeds.
typedef SourceAt = ({String id, Source source});
