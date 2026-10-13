import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/updates/update.dart';
import 'package:openlauncher/core/updates/update_source.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Where the launcher stands, for anything that shows it. In a browser, the
/// TV's.
final updateStateProvider = Provider<UpdateState>(
  (ref) => ref.watch(updateControllerProvider),
);

/// Finds and installs releases of the launcher. What it returns is a message
/// for the user, its first line the heading.
class UpdateController extends Notifier<UpdateState> {
  Release? _latest;

  @override
  UpdateState build() => const UpdateState();

  UpdateSource get _source => ref.read(updateSourceProvider);

  Future<String> check() async {
    if (state.busy) return _busy;
    state = state.doing(UpdateStatus.checking);
    try {
      _latest = await _source.latest();
    } on Object catch (error) {
      state = state.failed('$error');
      return 'Could not check for updates\n$error';
    }
    state = UpdateState(latest: _latest?.version, notes: _latest?.notes ?? '');
    if (state.available) {
      return 'Update available\n'
          'OpenLauncher ${state.latest} can be installed.';
    }
    unawaited(_source.discard().catchError((Object _) {}));
    return 'Up to date\nOpenLauncher ${state.current} is the latest version.';
  }

  /// Downloads the latest release and has the TV install it. The launcher is
  /// restarted by it, so this only returns if there was nothing to install
  /// or it failed.
  Future<String> install() async {
    if (state.busy) return _busy;
    if (!state.available) {
      final said = await check();
      if (!state.available) return said;
    }
    final release = _latest!;
    state = state.doing(UpdateStatus.downloading);
    final String path;
    try {
      path = await _source.download(release, (progress) {
        // In whole percents: every change is sent to the editor.
        final shown = (progress * 100).floor() / 100;
        if (shown != state.progress) {
          state = state.doing(UpdateStatus.downloading, progress: shown);
        }
      });
    } on Object catch (error) {
      return _failed('$error');
    }
    state = state.doing(UpdateStatus.installing, progress: 1);
    try {
      return _failed(
        await ref.read(launcherPlatformProvider).installUpdate(path),
      );
    } on Object catch (error) {
      return _failed('$error');
    }
  }

  static const _busy = 'Busy\nAn update is already being worked on.';

  String _failed(String error) {
    state = state.failed(error);
    return 'The update was not installed\n$error';
  }
}

/// How long after starting the first check is made, and how often after.
const firstUpdateCheck = Duration(seconds: 30);
const updateCheckEvery = Duration(hours: 24);

/// How long the remote must have been left alone before an update installs
/// itself.
const autoInstallIdle = Duration(minutes: 5);

/// Checks for updates while the launcher runs, as the user's
/// [UpdateOptions] say, and in [UpdateMode.auto] installs what it finds once
/// the TV is showing the launcher and nobody is using it.
final updateScheduleProvider = Provider<void>((ref) {
  final mode = ref.watch(
    configProvider.select((config) => config.value?.updates.mode),
  );
  if (mode == null || mode == UpdateMode.off) return;
  final updates = ref.read(updateControllerProvider.notifier);
  final first = Timer(firstUpdateCheck, updates.check);
  final daily = Timer.periodic(updateCheckEvery, (_) => updates.check());
  ref
    ..onDispose(first.cancel)
    ..onDispose(daily.cancel);
  if (mode != UpdateMode.auto) return;

  final now = ref.read(nowProvider);
  var lastKey = now();
  bool onKey(KeyEvent event) {
    lastKey = now();
    return false;
  }

  HardwareKeyboard.instance.addHandler(onKey);
  final idle = Timer.periodic(const Duration(minutes: 1), (_) {
    final update = ref.read(updateControllerProvider);
    // A failed install waits for the next check.
    if (!update.available || update.status != UpdateStatus.idle) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (now().difference(lastKey) < autoInstallIdle) return;
    updates.install();
  });
  ref
    ..onDispose(() => HardwareKeyboard.instance.removeHandler(onKey))
    ..onDispose(idle.cancel);
});
