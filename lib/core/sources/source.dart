import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/values/template.dart';

/// Where rows come from, from a pack's `sources/<name>.json`:
/// `{url, every, watch, rows}`. `url` is `http(s)://...` or `os://<query>`.
@immutable
class Source {
  const Source(this.url, {this.every, this.watch = false, this.rows = ''});

  final Uri url;

  /// Seconds between reads; null reads once, or on change if [watch].
  final int? every;

  /// Read again when the source says it changed (`os://` only).
  final bool watch;

  /// Path to the list in the answer, e.g. `result.items`; empty for the
  /// answer itself.
  final String rows;

  bool get onDevice => url.isScheme('os');

  static Source? fromJson(Object? json) {
    if (json case {'url': final String text}) {
      final url = Uri.tryParse(text.trim());
      if (url == null ||
          !(url.isScheme('os') && url.host.isNotEmpty ||
              HttpFeed.addressOf(text) != null)) {
        return null;
      }
      return Source(
        url,
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
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'url': '$url',
    'every': ?every,
    if (watch) 'watch': true,
    if (rows.isNotEmpty) 'rows': rows,
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
      other.url == url &&
      other.every == every &&
      other.watch == watch &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(url, every, watch, rows);
}
