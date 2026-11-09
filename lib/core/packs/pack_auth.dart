import 'package:flutter/foundation.dart';
import 'package:openlauncher_domain/values/template.dart';

/// How a pack signs its requests, from `auth` in its `pack.json`: headers
/// that may hold secret settings, sent only to the address in [host].
@immutable
class PackAuthProfile {
  const PackAuthProfile(this.name, this.host, this.headers);

  static final _name = RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,39}$');

  final String name;

  /// A template over the plain settings; where the headers may be sent.
  final String host;

  /// Header name -> template over `settings`, secrets included.
  final Map<String, String> headers;

  static PackAuthProfile? fromJson(String name, Object? json) {
    if (!_name.hasMatch(name) ||
        json is! Map ||
        json['host'] is! String ||
        json['headers'] is! Map) {
      return null;
    }
    final headers = {
      for (final MapEntry(:key, :value) in (json['headers'] as Map).entries)
        if (key is String && value is String) key: value,
    };
    return headers.isEmpty
        ? null
        : PackAuthProfile(name, json['host'] as String, headers);
  }

  static Map<String, PackAuthProfile> mapFromJson(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) key: ?fromJson(key, value),
  };

  Map<String, Object?> toJson() => {'host': host, 'headers': headers};

  /// The headers for a request to [target], or null when [target] is not the
  /// profile's host or a setting it needs has no value. [settings] are the
  /// plain values and [secrets] the secret ones; a secret is never read into
  /// [host].
  Map<String, String>? headersFor(
    Uri target, {
    required Map<String, Object?> settings,
    required Map<String, String> secrets,
  }) {
    final origin = Uri.tryParse(
      Template.parse(host).render(_reading(settings)).trim(),
    );
    if (origin == null || !_sameOrigin(origin, target)) return null;
    final everything = {...settings, ...secrets};
    final filled = <String, String>{};
    for (final MapEntry(:key, :value) in headers.entries) {
      final template = Template.parse(value);
      if (template.roots.any((root) => root != 'settings')) return null;
      if (!_hasValues(value, everything)) return null;
      filled[key] = template.render(_reading(everything));
    }
    return filled;
  }

  static Object? Function(String) _reading(Map<String, Object?> settings) =>
      (root) => root == 'settings' ? settings : null;

  static final _settingNamed = RegExp(r'settings\.(\w+)');

  /// Whether every `settings.x` the template names has a value.
  static bool _hasValues(String template, Map<String, Object?> values) =>
      _settingNamed
          .allMatches(template)
          .every((named) => '${values[named[1]] ?? ''}'.isNotEmpty);

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  @override
  bool operator ==(Object other) =>
      other is PackAuthProfile &&
      other.name == name &&
      other.host == host &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(name, host);
}
