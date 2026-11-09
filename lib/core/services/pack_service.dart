import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';

/// Installed packs, as the user's config sees them.
class PackService {
  PackService(this._ref);

  final Ref _ref;

  PackStore get _store => _ref.read(packStoreProvider);

  /// Removes pack [id] unless it is built in or another pack needs it. What
  /// the config uses of it is left to show as missing; the editor warns first.
  Future<void> delete(String id) async {
    await _store.delete(id);
    await _ref.read(packSecretsProvider.notifier).forget(id);
  }

  /// Keeps [value] as the secret setting [key] of [packId]. No value (a
  /// delete) clears it; a blank one is refused, so a secret is only ever
  /// cleared on purpose.
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
    if (value is String && value.isEmpty) {
      throw const FormatException('A secret cannot be blank; delete it');
    }
    await _ref
        .read(packSecretsProvider.notifier)
        .set(packId!, setting.key, (value as String?) ?? '');
  }
}

final packServiceProvider = Provider<PackService>(PackService.new);
