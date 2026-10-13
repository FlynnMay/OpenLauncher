import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

export 'package:openlauncher/platform/launcher_platform.dart' show Access;

/// Whether the user has allowed the launcher an [Access] in the TV's
/// settings. In a browser, the TV's answer.
final accessProvider = FutureProvider.family<bool, Access>(
  (ref, access) => ref.watch(launcherPlatformProvider).hasAccess(access),
);

/// How each [Access] is put to the user.
extension AccessWording on Access {
  String get label => switch (this) {
    Access.homeButton => 'Home button',
    Access.notifications => 'Notifications',
  };

  /// What it is for.
  String get use => switch (this) {
    Access.homeButton => "The remote's Home button opens OpenLauncher.",
    Access.notifications =>
      "Shows other apps' notifications and what is playing.",
  };
}
