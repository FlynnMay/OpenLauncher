import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';
import 'package:openlauncher_domain/values/template.dart';

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

  /// What the search setting [key] of [packId] finds for [query]: each hit
  /// as it is listed, and the value choosing it keeps.
  Future<List<({String title, Map<String, Object?> value})>> search(
    String? packId,
    String? key,
    String? query,
  ) async {
    final setting = settingOf(
      await _ref.read(packsProvider.future),
      packId,
      key,
    );
    final source = setting?.search;
    if (setting == null || source == null) {
      throw const FormatException('"pack" and "key" must name a search');
    }
    if (query == null || query.trim().isEmpty) {
      throw const FormatException('"q" must say what to look for');
    }
    final address = HttpFeed.addressOf(
      Template.parse(source.address).render(
        (root) =>
            root == 'query' ? Uri.encodeQueryComponent(query.trim()) : null,
      ),
    );
    if (address == null) {
      throw FormatException('"$packId" has no address for ${setting.label}');
    }
    final answer = await _ref.read(feedFetcherProvider)(
      HttpFeed('$packId:$key', address, source.every ?? 60),
    );
    return [for (final row in source.rowsOf(answer)) ?setting.chosenFrom(row)];
  }
}

final packServiceProvider = Provider<PackService>(PackService.new);
