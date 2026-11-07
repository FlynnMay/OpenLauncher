import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/screens/screens.dart';

/// Which screen is shown, and the screens there are. Where a screen is named
/// by `id`, none means the one shown. Each returns a message for the user, or
/// null.
class ScreenService {
  ScreenService(this._ref);

  final Ref _ref;

  Future<String?> open(String id) async {
    if (await _screenNamed(id) == null) return 'There is no screen "$id".';
    _ref.read(shownScreensProvider.notifier).open(id);
    return null;
  }

  String? back() {
    if (_ref.read(shownScreensProvider.notifier).back()) return null;
    return 'There is no screen before.';
  }

  /// An empty screen. [id] is wanted, not promised; [name] is its label.
  Future<String?> add({String? id, String name = ''}) async {
    final layout = await _layout();
    final free = freeId(id ?? slugOf(name, 'screen'), layout.itemIds);
    final empty = Screen.empty(free);
    await _edit(
      (layout) => layout.copyWith(
        screens: [
          ...layout.screens,
          empty.withRoot(empty.root.copyWith(name: name)),
        ],
      ),
    );
    return 'Screen "$free" was added.';
  }

  Future<String?> remove({String? id}) async {
    final screen = await _screenNamed(id);
    if (screen == null) return _noSuchScreen;
    if ((await _layout()).screens.length < 2) return 'The last screen stays.';
    await _edit(
      (layout) => layout.copyWith(
        screens: [
          for (final one in layout.screens)
            if (one.id != screen.id) one,
        ],
      ),
    );
    return 'Screen "${screen.id}" was removed.';
  }

  Future<String?> rename({String? id, required String name}) async {
    final screen = await _screenNamed(id);
    if (screen == null) return _noSuchScreen;
    await _edit(
      (layout) => layout.copyWith(
        screens: [
          for (final one in layout.screens)
            one.id == screen.id
                ? one.withRoot(one.root.copyWith(name: name))
                : one,
        ],
      ),
    );
    return null;
  }

  Future<String?> duplicate({String? id}) async {
    final original = await _screenNamed(id);
    if (original == null) return _noSuchScreen;
    final free = freeId(original.id, (await _layout()).itemIds);
    final (:screen, :renamed) = original.copied(free);
    await _ref
        .read(configProvider.notifier)
        .change(
          (config) => config.copyWith(
            // Pictures set on a node go with its copy.
            iconOverrides: _picturesCopied(config.iconOverrides, renamed),
            iconSources: _picturesCopied(config.iconSources, renamed),
            layout: config.layout.copyWith(
              screens: [
                for (final one in config.layout.screens) ...[
                  one,
                  if (one.id == original.id) screen,
                ],
              ],
            ),
          ),
        );
    return 'Screen "$free" was added.';
  }

  /// The screen to open on, none to keep it; [remember] opens on the screen
  /// shown last instead, none to keep that.
  Future<String?> startup({String? id, bool? remember}) async {
    if (id != null && await _screenNamed(id) == null) {
      return 'There is no screen "$id".';
    }
    await _edit(
      (layout) => layout.copyWith(
        startup: Startup(
          id ?? layout.startup.screen,
          remember: remember ?? layout.startup.remember,
        ),
      ),
    );
    return null;
  }

  static const _noSuchScreen = 'There is no such screen.';

  Future<Layout> _layout() async =>
      (await _ref.read(configProvider.future)).layout;

  /// The screen [id] names; none, the one shown. Null if there is none.
  Future<Screen?> _screenNamed(String? id) async => id == null
      ? _ref.read(currentScreenProvider)
      : (await _layout()).screen(id);

  Future<void> _edit(Layout Function(Layout layout) change) async {
    final layout = await _layout();
    await _ref.read(configProvider.notifier).setLayout(change(layout));
  }

  /// [pictures] with the entries of the nodes in [renamed] repeated for
  /// their new ids.
  static Map<String, String> _picturesCopied(
    Map<String, String> pictures,
    Map<String, String> renamed,
  ) => {
    ...pictures,
    for (final MapEntry(:key, :value) in renamed.entries)
      Layout.pictureKey(value): ?pictures[Layout.pictureKey(key)],
  };
}

final screenServiceProvider = Provider<ScreenService>(ScreenService.new);
