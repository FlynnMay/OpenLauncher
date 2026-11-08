import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/services/overlay_service.dart';
import 'package:openlauncher_domain/commands/commands.dart';

/// Which screen is shown, and the screens there are. Where a screen is named
/// by `id`, none means the one shown. Each returns a message for the user, or
/// null.
class ScreenService {
  ScreenService(this._ref);

  final Ref _ref;

  Future<String?> open(String id) async {
    if (await _screenNamed(id) == null) return 'There is no screen "$id".';
    if (_screens.open(id)) _closeOverlays();
    return null;
  }

  String? back() {
    if (!_screens.back()) return 'There is no screen before.';
    _closeOverlays();
    return null;
  }

  ShownScreen get _screens => _ref.read(shownScreensProvider.notifier);

  /// What was open over the screen left behind.
  void _closeOverlays() => _ref.read(overlayServiceProvider).closeAll();

  /// An empty screen. [id] is wanted, not promised; [name] is its label.
  Future<String?> add({String? id, String name = ''}) async {
    final command = AddScreen(id: id, name: name);
    final free = command.idIn(await _layout());
    await _ref.read(commandsProvider).run(command);
    return 'Screen "$free" was added.';
  }

  Future<String?> remove({String? id}) async {
    final screen = await _screenNamed(id);
    if (screen == null) return noSuchScreen;
    try {
      await _ref.read(commandsProvider).run(RemoveScreen(screen.id));
    } on CommandRefused catch (refused) {
      return refused.message;
    }
    return 'Screen "${screen.id}" was removed.';
  }

  Future<String?> rename({String? id, required String name}) async {
    final screen = await _screenNamed(id);
    if (screen == null) return noSuchScreen;
    await _ref.read(commandsProvider).run(RenameScreen(screen.id, name));
    return null;
  }

  Future<String?> duplicate({String? id}) async {
    final original = await _screenNamed(id);
    if (original == null) return noSuchScreen;
    final command = DuplicateScreen(original.id);
    final copyId = command.copyIdIn(await _layout());
    await _ref.read(commandsProvider).run(command);
    return 'Screen "$copyId" was added.';
  }

  /// The screen to open on, none to keep it; [remember] opens on the screen
  /// shown last instead, none to keep that.
  Future<String?> startup({String? id, bool? remember}) async {
    if (id != null && await _screenNamed(id) == null) {
      return 'There is no screen "$id".';
    }
    await _ref
        .read(commandsProvider)
        .run(SetStartup(screenId: id, remember: remember));
    return null;
  }

  Future<Layout> _layout() async =>
      (await _ref.read(configProvider.future)).layout;

  /// The screen [id] names; none, the one shown. Null if there is none.
  Future<Screen?> _screenNamed(String? id) async => id == null
      ? _ref.read(currentScreenProvider)
      : (await _layout()).screen(id);
}

final screenServiceProvider = Provider<ScreenService>(ScreenService.new);
