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
    final setting = await _setting(packId, key);
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

  /// Throws unless every value in [settings] is for a plain setting of an
  /// installed pack and fits its type. Secrets do not go this way.
  Future<void> checkSettings(Object? settings) async {
    if (settings is! Map) throw const FormatException('Expected an object');
    for (final MapEntry(:key, :value) in settings.entries) {
      await _checkValuesOf('$key', value);
    }
  }

  Future<void> _checkValuesOf(String packId, Object? values) async {
    if (values is! Map) throw FormatException('Settings of $packId unreadable');
    for (final MapEntry(:key, :value) in values.entries) {
      final setting = await _setting(packId, '$key');
      if (setting == null || setting.secret || !setting.accepts(value)) {
        throw FormatException('Not a setting of $packId: $key');
      }
    }
  }

  Future<PackSetting?> _setting(String? packId, String? key) async {
    final packs = await _ref.read(packsProvider.future);
    for (final pack in packs) {
      if (pack.id == packId) {
        return pack.settings.where((setting) => setting.key == key).firstOrNull;
      }
    }
    return null;
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
