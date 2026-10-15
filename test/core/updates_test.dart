import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';
import '../support/updates.dart';

void main() {
  test('a version is later by its numbers, not its text', () {
    expect(isLaterVersion('0.1.1', '0.1.0'), isTrue);
    expect(isLaterVersion('v0.10.0', '0.9.9'), isTrue);
    expect(isLaterVersion('1.0.0', '0.99.99'), isTrue);
    expect(isLaterVersion('0.1.0', '0.1.0'), isFalse);
    expect(isLaterVersion('0.1.0', '0.1.1'), isFalse);
    // What is not a version is never later.
    expect(isLaterVersion('nightly', '0.1.0'), isFalse);
    expect(isLaterVersion('0.2.0-beta', '0.1.0'), isFalse);
  });

  group('a release on GitHub', () {
    Map<String, Object?> json({String tag = 'v0.2.0', String? apk}) => {
      'tag_name': tag,
      'body': 'What changed.\n',
      'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'https://x/n', 'size': 1},
        {
          'name': apk ?? 'openlauncher-0.2.0.apk',
          'browser_download_url': 'https://x/openlauncher-0.2.0.apk',
          'size': 42,
          'digest': 'sha256:ABCDEF',
        },
      ],
    };

    test('is read: its version, APK, size, hash and notes', () {
      final read = Release.fromGitHub(json())!;
      expect(read.version, '0.2.0');
      expect(read.apk, Uri.parse('https://x/openlauncher-0.2.0.apk'));
      expect(
        (read.bytes, read.sha256, read.notes),
        (42, 'abcdef', 'What changed.'),
      );
    });

    test('is passed over without an APK or a version for a tag', () {
      expect(Release.fromGitHub(json(apk: 'source.zip')), isNull);
      expect(Release.fromGitHub(json(tag: 'nightly')), isNull);
      expect(Release.fromGitHub('nonsense'), isNull);
    });
  });

  group('the GitHub source', () {
    final bytes = utf8.encode('an apk, as far as this goes');
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('openlauncher_update');
      addTearDown(() => tmp.delete(recursive: true));
    });

    GitHubUpdateSource source(http.Client client) =>
        GitHubUpdateSource(client: client, directory: () async => tmp);

    Release apk({int? size, String? hash}) => Release(
      version: later,
      apk: Uri.parse('https://x/update.apk'),
      bytes: size ?? bytes.length,
      sha256: hash ?? sha256.convert(bytes).toString(),
    );

    final serving = MockClient(
      (request) async => http.Response.bytes(bytes, 200),
    );

    test('asks the repository for its latest release', () async {
      final asked = <Uri>[];
      final found = await source(
        MockClient((request) async {
          asked.add(request.url);
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.2.0',
              'assets': [
                {
                  'name': 'openlauncher-0.2.0.apk',
                  'browser_download_url': 'https://x/a.apk',
                  'size': 9,
                },
              ],
            }),
            200,
          );
        }),
      ).latest();
      expect(found?.version, '0.2.0');
      expect(
        asked.single.toString(),
        contains('/repos/$updateRepo/releases/latest'),
      );
    });

    test('finds nothing where none is published, and says when refused', () {
      expect(
        source(MockClient((_) async => http.Response('', 404))).latest(),
        completion(isNull),
      );
      expect(
        source(MockClient((_) async => http.Response('', 403))).latest(),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('says in words that GitHub could not be reached', () {
      for (final (thrown, said) in [
        (http.ClientException('Connection refused'), 'could not be reached'),
        (const SocketException('No route to host'), 'could not be reached'),
        (TimeoutException('20 s'), 'did not answer in time'),
      ]) {
        final failing = source(MockClient((_) => throw thrown));
        final words = isA<UpdateFailure>().having(
          (failure) => failure.message,
          'message',
          contains(said),
        );
        expect(failing.latest(), throwsA(words));
        expect(failing.download(apk(), (_) {}), throwsA(words));
      }
      expect(
        source(MockClient((_) async => http.Response('<html>', 200))).latest(),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('downloads the APK and tells how far it is', () async {
      final progress = <double>[];
      final path = await source(serving).download(apk(), progress.add);
      expect(File(path).readAsBytesSync(), bytes);
      expect(progress.last, 1);
      await source(serving).discard();
      expect(File(path).existsSync(), isFalse);
    });

    test('refuses one that is not the size or the hash the release said', () {
      expect(
        source(serving).download(apk(size: bytes.length + 1), (_) {}),
        throwsA(isA<UpdateFailure>()),
      );
      expect(
        source(serving).download(apk(size: bytes.length - 1), (_) {}),
        throwsA(isA<UpdateFailure>()),
      );
      expect(
        source(serving).download(apk(hash: 'f' * 64), (_) {}),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });

  group('the launcher', () {
    late FakeUpdateSource source;
    late FakeLauncherPlatform platform;
    late ProviderContainer container;

    setUp(() {
      source = FakeUpdateSource(release(later));
      platform = FakeLauncherPlatform(const [], const []);
      container = ProviderContainer(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          updateSourceProvider.overrideWithValue(source),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(container.dispose);
    });

    UpdateState state() => container.read(updateStateProvider);
    Future<String?> act(String action) => container
        .read(actionRunnerProvider)
        .run(Act(action, const {entityArg: 'system:updates'}));

    test('is told of a later release when it checks', () async {
      expect(
        (state().current, state().latest, state().available),
        (appVersion, null, false),
      );
      expect(await act('check'), startsWith('Update available'));
      expect(
        (state().latest, state().available, state().notes),
        (later, true, 'Fixes.'),
      );
      expect(state().summary, 'Version $later is available');
    });

    test('is up to date with the release it is, or with none', () async {
      source.found = release(appVersion);
      expect(await act('check'), startsWith('Up to date'));
      expect((state().latest, state().available), (appVersion, false));
      // What an earlier download left is cleared away.
      expect(source.discarded, isTrue);
      source.found = null;
      await act('check');
      expect(state().available, isFalse);
    });

    test('says so when it could not ask', () async {
      source.failure = const UpdateFailure('GitHub answered 403.');
      expect(await act('check'), contains('GitHub answered 403.'));
      expect(
        (state().status, state().error),
        (UpdateStatus.failed, 'GitHub answered 403.'),
      );
    });

    test('downloads the release and hands it to the TV to install', () async {
      final seen = <UpdateStatus>[];
      container.listen(
        updateControllerProvider,
        (_, next) => seen.add(next.status),
      );
      // The fake TV does not install: the real one never answers.
      final said = await act('install');
      expect(source.downloaded, [later]);
      expect(platform.installed, ['/cache/update.apk']);
      expect(
        seen,
        containsAllInOrder([
          UpdateStatus.checking,
          UpdateStatus.downloading,
          UpdateStatus.installing,
          UpdateStatus.failed,
        ]),
      );
      expect(said, contains('There is no TV here.'));
      expect(state().available, isTrue);
    });

    test('installs nothing when there is nothing later', () async {
      source.found = release(appVersion);
      expect(await act('install'), startsWith('Up to date'));
      expect(source.downloaded, isEmpty);
      expect(platform.installed, isEmpty);
    });

    test('says why the TV did not install it', () async {
      platform.installRefusal = 'It was cancelled on the TV.';
      expect(await act('install'), endsWith('It was cancelled on the TV.'));
      expect(state().status, UpdateStatus.failed);
    });

    test('does not hand over a download that failed', () async {
      await act('check');
      source.failure = const UpdateFailure('The download does not match.');
      expect(await act('install'), contains('does not match'));
      expect(platform.installed, isEmpty);
    });

    test('has its standing read like any entity', () async {
      await act('check');
      await container.read(entitiesProvider.future);
      final sub = container.listen(
        entityDataProvider('system:updates'),
        (_, _) {},
      );
      // Its values come through its source, a moment later.
      await pumpEventQueue();
      expect(sub.read(), {
        'id': 'system:updates',
        'label': 'Updates',
        'category': 'updates',
        'text': appVersion,
        'current': appVersion,
        'latest': later,
        'available': true,
        'status': 'idle',
        'progress': 0.0,
        'notes': 'Fixes.',
        'error': null,
      });
    });

    test('keeps what is done about updates in its config', () async {
      expect(LauncherConfig().updates.mode, UpdateMode.notify);
      final config = LauncherConfig().patched({
        'updates': {'mode': 'auto'},
      });
      expect(config.updates.mode, UpdateMode.auto);
      expect(
        LauncherConfig.fromJson(config.toJson()).updates.mode,
        UpdateMode.auto,
      );
      expect(UpdateOptions.fromJson({'mode': 'odd'}).mode, UpdateMode.notify);
    });

    test('tells the editor where it stands', () async {
      await act('check');
      final sent = jsonDecode(jsonEncode(state().toJson()));
      expect(UpdateState.fromJson(sent), state());
      expect(UpdateState.fromJson(null), const UpdateState());
    });
  });
}
