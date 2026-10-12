import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/updates/update.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The GitHub repository releases are published in.
const updateRepo = 'FlynnMay/OpenLauncher';

/// Largest APK taken.
const maxUpdateBytes = 200 * 1024 * 1024;

/// Why an update could not be found or fetched, in words for the user.
class UpdateFailure implements Exception {
  const UpdateFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where releases come from.
abstract interface class UpdateSource {
  /// The latest release, or null if there is none.
  Future<Release?> latest();

  /// Downloads [release]'s APK, checks it against the release's size and
  /// hash, and returns its path. [onProgress] is told how far, 0 to 1.
  Future<String> download(Release release, void Function(double) onProgress);

  /// Deletes what [download] left.
  Future<void> discard();
}

/// On a TV, GitHub; anywhere else there is nothing to install.
final updateSourceProvider = Provider<UpdateSource>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? GitHubUpdateSource()
      : const NoUpdateSource(),
);

class NoUpdateSource implements UpdateSource {
  const NoUpdateSource();

  @override
  Future<Release?> latest() async => null;

  @override
  Future<String> download(Release release, void Function(double) onProgress) =>
      throw const UpdateFailure('Updates are installed on the TV.');

  @override
  Future<void> discard() async {}
}

class GitHubUpdateSource implements UpdateSource {
  GitHubUpdateSource({http.Client? client, this.directory})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Where the download is kept; the app's cache when null.
  final Future<Directory> Function()? directory;

  static final _latest = Uri.https(
    'api.github.com',
    '/repos/$updateRepo/releases/latest',
  );

  Future<File> _file() async {
    final dir = await (directory ?? getTemporaryDirectory)();
    return File(p.join(dir.path, 'update.apk'));
  }

  /// [work], with a failure to reach GitHub put in words.
  static Future<T> _reached<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on TimeoutException {
      throw const UpdateFailure('GitHub did not answer in time.');
    } on IOException {
      throw const UpdateFailure('GitHub could not be reached.');
    } on http.ClientException {
      throw const UpdateFailure('GitHub could not be reached.');
    } on FormatException {
      throw const UpdateFailure("GitHub's answer could not be read.");
    }
  }

  @override
  Future<Release?> latest() => _reached(_askLatest);

  @override
  Future<String> download(Release release, void Function(double) onProgress) =>
      _reached(() => _fetch(release, onProgress));

  Future<Release?> _askLatest() async {
    final response = await _client
        .get(_latest, headers: const {'accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    // No release has been published.
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UpdateFailure('GitHub answered ${response.statusCode}.');
    }
    return Release.fromGitHub(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<String> _fetch(
    Release release,
    void Function(double) onProgress,
  ) async {
    if (release.bytes <= 0 || release.bytes > maxUpdateBytes) {
      throw const UpdateFailure('The update is not a size that is accepted.');
    }
    final file = await _file();
    final response = await _client
        .send(http.Request('GET', release.apk))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateFailure('The download answered ${response.statusCode}.');
    }
    final digest = _Digest();
    final hash = sha256.startChunkedConversion(digest);
    final out = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        got += chunk.length;
        if (got > release.bytes) break;
        out.add(chunk);
        hash.add(chunk);
        onProgress(got / release.bytes);
      }
    } finally {
      await out.close();
      hash.close();
    }
    if (got != release.bytes) {
      throw const UpdateFailure('The download is not the size it should be.');
    }
    if (release.sha256 case final expected?
        when digest.value.toString() != expected) {
      throw const UpdateFailure('The download does not match the release.');
    }
    return file.path;
  }

  @override
  Future<void> discard() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

class _Digest implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
