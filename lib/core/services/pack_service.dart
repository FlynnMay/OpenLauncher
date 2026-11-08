import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';

/// Installed packs, as the user's config sees them.
class PackService {
  PackService(this._ref);

  final Ref _ref;

  PackStore get _store => _ref.read(packStoreProvider);

  /// Removes pack [id] unless it is built in, another pack needs it or the
  /// config uses it.
  Future<void> delete(String id) async {
    final pack = await _store.removable(id);
    _refuseIfInUse(pack, await _ref.read(configProvider.future));
    await _store.delete(id);
    await _ref.read(packSecretsProvider.notifier).forget(id);
  }

  /// Keeps [value] as the secret setting [key] of [packId]; no value clears it.
  Future<void> setSecret(String? packId, String? key, Object? value) async {
    final setting = settingOf(
      await _ref.read(packsProvider.future),
      packId,
      key,
    );
    if (setting == null || !setting.secret) {
      throw const FormatException('"pack" and "key" must name a secret');
    }
    if (value != null && value is! String) {
      throw const FormatException('"value" must be text');
    }
    await _ref
        .read(packSecretsProvider.notifier)
        .set(packId!, setting.key, (value as String?) ?? '');
  }

  void _refuseIfInUse(Pack pack, LauncherConfig config) {
    final uses = pack.usesIn(config.toJson());
    if (uses == 0) return;
    throw PackRefused(
      409,
      '"${pack.name}" is in use in $uses ${uses == 1 ? 'place' : 'places'}',
    );
  }
}

final packServiceProvider = Provider<PackService>(PackService.new);
