import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Whatever is playing.
class MediaService {
  MediaService(this._ref);

  final Ref _ref;

  Future<String?> send(MediaCommand command) async {
    await _ref.read(launcherPlatformProvider).sendMediaCommand(command);
    return null;
  }
}

final mediaServiceProvider = Provider<MediaService>(MediaService.new);
