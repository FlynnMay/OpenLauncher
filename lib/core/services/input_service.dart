import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// The TV's inputs.
class InputService {
  InputService(this._ref);

  final Ref _ref;

  Future<String?> switchTo(String inputId) async {
    await _ref.read(launcherPlatformProvider).switchToInput(inputId);
    return null;
  }
}

final inputServiceProvider = Provider<InputService>(InputService.new);
