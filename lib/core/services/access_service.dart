import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What the TV allows the launcher.
class AccessService {
  AccessService(this._ref);

  final Ref _ref;

  /// Takes the user to the TV's own screen to allow or withdraw [access]. The
  /// message's first line is its heading.
  Future<String?> change(Access access) async {
    try {
      await _ref.read(launcherPlatformProvider).changeAccess(access);
    } on PlatformException {
      return 'This TV has no screen for it\n'
          'It can be allowed from a computer instead. The OpenLauncher '
          'README says how.';
    }
    _ref.invalidate(accessProvider(access));
    return null;
  }
}

final accessServiceProvider = Provider<AccessService>(AccessService.new);
