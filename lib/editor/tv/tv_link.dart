import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/media/media_dirs.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/editor/editing/editor_mode.dart';
import 'package:openlauncher/editor/editing/history.dart';
import 'package:openlauncher/editor/tv/tv_api.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

/// Provider overrides that run the launcher in a browser: config, entities
/// and wallpapers come from the TV, and config changes go back to it.
final List<Override> tvOverrides = [
  commandsProvider.overrideWith(
    (ref) => TvCommands(
      ref.watch(tvApiProvider),
      onRan: ref.read(historyProvider.notifier).recordChange,
    ),
  ),
  configStoreProvider.overrideWith(
    // A new store per state, so the config is re-read.
    (ref) => TvConfigStore(ref.watch(tvStateProvider.future)),
  ),
  entitiesProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).entities,
  ),
  packsProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).packs,
  ),
  packReaderProvider.overrideWith((ref) => ref.watch(tvApiProvider).packFile),
  actionRunnerProvider.overrideWith(
    (ref) => TvActionRunner(
      ref,
      ref.watch(tvApiProvider),
      () => ref.read(editorModeProvider),
    ),
  ),
  accessProvider.overrideWith(
    (ref, access) async =>
        (await ref.watch(tvStateProvider.future)).access[access] ?? true,
  ),
  updateStateProvider.overrideWith(
    (ref) => ref.watch(tvStateProvider).value?.update ?? const UpdateState(),
  ),
  launcherPlatformProvider.overrideWith((ref) {
    final platform = BrowserPlatform();
    ref.listen(tvStateProvider, (_, next) {
      if (next.value case final state?) platform.hear(state.nowPlaying);
    }, fireImmediately: true);
    return platform;
  }),
  // Browsers cannot make cross-site requests; the TV can.
  feedFetcherProvider.overrideWith((ref) {
    final api = ref.watch(tvApiProvider);
    return (feed) => api.feedValue(feed.id);
  }),
  // The page is the config server's guest; it does not run one.
  configServerProvider.overrideWith((ref) async => null),
  // Uploaded files are reached on the TV.
  mediaPathProvider.overrideWith(
    (ref) async =>
        (_, id) => ref.watch(tvApiProvider).mediaUrl(id),
  ),
];

/// The TV's config, as the TV last said it. The page does not keep it: it
/// sends edits, and the TV answers with the new state.
class TvConfigStore implements ConfigStore {
  TvConfigStore(this._state);

  final Future<TvState> _state;

  @override
  Future<LauncherConfig> load() async => (await _state).config;

  @override
  Future<void> save(LauncherConfig config) async {
    throw StateError('The config is changed with edits, not saved.');
  }
}

/// The browser's "device": nothing of its own. Entities arrive from the TV
/// and device actions are sent to it.
class BrowserPlatform extends FakeLauncherPlatform {
  BrowserPlatform() : super(const [], const []);

  void hear(NowPlaying? now) {
    playing = now;
    notifyNowPlayingChanged();
  }
}

/// Where an act goes depends on the [EditorMode]. Editing sends device
/// operations to the TV, as the act that asked for them, and runs the rest
/// here. Testing runs the rest here and says what the TV would have done.
/// Remote sends everything to the TV.
class TvActionRunner extends ActionRunner {
  TvActionRunner(super.ref, this._api, this._mode);

  final TvApi _api;
  final EditorMode Function() _mode;

  /// The TV's own updater and web requests (it holds the secrets), as well as
  /// what only the TV can do.
  static bool _onTv(Operation operation) =>
      operation.onDevice ||
      operation.address.startsWith('${Operation.launcher}updates/') ||
      isWebAddress(operation.address);

  @override
  Future<String?> carryOut(Operation operation, Act act, OperationRun run) =>
      switch (_mode()) {
        EditorMode.remote => _api.act(act),
        EditorMode.test when _onTv(operation) => Future.value(
          _wouldHaveDone(operation, run),
        ),
        EditorMode.edit when _onTv(operation) => _api.act(act),
        _ => super.carryOut(operation, act, run),
      };

  static String _wouldHaveDone(Operation operation, OperationRun run) {
    final label = operation.label;
    final what = label.substring(0, 1).toLowerCase() + label.substring(1);
    final given = run.args.entries.map((e) => '${e.key}: ${e.value}');
    return 'Test: would $what${given.isEmpty ? '' : ' (${given.join(', ')})'}';
  }
}
