import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/launcher_platform.dart';

/// Whether the remote's Home button opens this launcher. Re-checked whenever
/// the app comes back to the front, since it can be changed in the TV's
/// settings.
final homeButtonEnabledProvider = FutureProvider<bool>((ref) {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  return ref.watch(launcherPlatformProvider).isHomeButtonEnabled();
});

/// Whether the app may switch the Home button on and off itself, which it can
/// once automatic setup has run.
final canManageHomeButtonProvider = FutureProvider<bool>(
  (ref) => ref.watch(launcherPlatformProvider).canManageHomeButton(),
);
