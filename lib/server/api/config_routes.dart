import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The layout and the settings kept beside it.
class ConfigRoutes implements ApiRoutes {
  ConfigRoutes(this._ref);

  final Ref _ref;

  @override
  void addTo(Router router) {
    router
      ..put('/api/layout', _replaceLayout)
      ..delete('/api/layout', _resetLayoutToStarting)
      ..put('/api/config', _setSettings);
  }

  Future<Response> _replaceLayout(Request request) async {
    final layout = Layout.fromJson(await readJsonObject(request));
    return revisionResponse(
      _ref
          .read(commandsProvider)
          .run(
            EditSlice([
              SliceEdit(const ConfigAddress(), [SetLayout(layout)]),
            ]),
            session: editingSessionOf(request),
          ),
    );
  }

  Future<Response> _resetLayoutToStarting(Request request) => revisionResponse(
    _ref
        .read(commandsProvider)
        .run(
          EditSlice([
            const SliceEdit(ConfigAddress(), [ResetLayout()]),
          ]),
          session: editingSessionOf(request),
        ),
  );

  /// Sets the config keys in the body; files are named by id. Unreadable
  /// values fall back to defaults instead of failing.
  Future<Response> _setSettings(Request request) async {
    final body = await readJsonObject(request);
    if (LauncherConfig.settingsValidationError(body) case final reason?) {
      throw FormatException(reason);
    }
    final values = await _ref.read(mediaStoreProvider).withPaths(body);
    return revisionResponse(
      _ref
          .read(commandsProvider)
          .run(
            EditSlice([
              SliceEdit(const ConfigAddress(), [
                for (final MapEntry(:key, :value) in values.entries)
                  SetSetting(key, value),
              ]),
            ]),
            session: editingSessionOf(request),
          ),
    );
  }
}
