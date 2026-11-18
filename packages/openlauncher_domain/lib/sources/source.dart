import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';
import 'package:openlauncher_domain/values/template.dart';
import 'package:openlauncher_domain/values/template_fill.dart';
import 'package:openlauncher_domain/variables/variable.dart';

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
    this.variables = const {},
  });

  static const methods = ['GET', 'POST'];

  /// Names a source's variables cannot take: what its fetch and its
  /// generator read their own slots by.
  static const reservedVariables = {'settings', 'row', 'tables'};

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

  /// The pack whose settings fill the templates. Never read from JSON: only
  /// the launcher says whose a source is, as it reads the pack's files.
  final String? pack;

  /// What a caller may give it, by name: `{{location}}` in its address or
  /// body reads the value given, or the variable's own value.
  final Variables variables;

  /// Whether the launcher answers it rather than the web.
  bool get answeredHere =>
      address.startsWith('os://') || address.startsWith('launcher://');

  bool get isTemplate => address.contains('{{');

  /// The address up to its area, e.g. `os://apps`: what answers it here.
  String get endpoint {
    final url = Uri.parse(address);
    return '${url.scheme}://${url.host}';
  }

  Source inPack(String packId) => _copy(pack: packId);

  /// This with another [address].
  Source withAddress(String address) => _copy(address: address);

  Source _copy({String? address, String? pack, Object? body = _same}) => Source(
    address ?? this.address,
    every: every,
    watch: watch,
    rows: rows,
    method: method,
    auth: auth,
    body: identical(body, _same) ? this.body : body,
    pack: pack ?? this.pack,
    variables: variables,
  );

  static const Object _same = Object();

  /// This asked with [given]: each variable is the one given, or when that
  /// is blank its own value read over [settings]. The variables' slots of
  /// the request are filled; `{{settings...}}` ones stay for the fetch. Null
  /// while a required variable has no value.
  AskedSource? askedWith(
    Map<String, Object?> given,
    Map<String, Object?> settings,
  ) {
    Object? read(String template) =>
        Template.parse(template)
            .evaluate((root) => root == 'settings' ? settings : null);
    final values = {
      for (final MapEntry(:key, :value) in variables.entries)
        key: switch (given[key]) {
          final Object? one when !_blank(one) => one,
          _ => value.result(read),
        },
    };
    final lacking = variables.entries.any(
      (variable) => variable.value.required && _blank(values[variable.key]),
    );
    return lacking ? null : (params: values, request: _filled(values));
  }

  Source _filled(Map<String, Object?> values) {
    if (variables.isEmpty) return this;
    Object? fill(Object? json) =>
        fillSlots(json, values.keys.toSet(), (root) => values[root]);
    return _copy(address: '${fill(address)}', body: fill(body));
  }

  static bool _blank(Object? value) =>
      value == null ||
      value is String && value.trim().isEmpty ||
      value is Map && value.isEmpty;

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
        variables: variablesFromJson(json['variables']),
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
    if (variables.isNotEmpty)
      'variables': {
        for (final MapEntry(:key, :value) in variables.entries)
          key: value.toJson(),
      },
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
      jsonEncode(other.variables.map((k, v) => MapEntry(k, v.toJson()))) ==
          jsonEncode(variables.map((k, v) => MapEntry(k, v.toJson()))) &&
      jsonEncode(other.body) == jsonEncode(body);

  @override
  int get hashCode =>
      Object.hash(address, every, watch, rows, method, auth, pack);
}

/// A source asked with arguments: the value of each of its variables, and the
/// source with them filled in.
typedef AskedSource = ({Map<String, Object?> params, Source request});

/// A source, and what its fetch is known by: `<pack>:<name>` for a pack's,
/// so every reader shares one, else the entity it feeds.
typedef SourceAt = ({String id, Source source});
