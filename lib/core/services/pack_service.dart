import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/source_request.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/sources/source.dart';
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

  /// The options the setting [key] of [packId] finds for [query], each as it
  /// is listed, and the value choosing it keeps.
  Future<List<FieldHit>> options(
    String? packId,
    String? key,
    String? query,
  ) async {
    final setting = settingOf(
      await _ref.read(packsProvider.future),
      packId,
      key,
    );
    final from = setting?.spec.from;
    if (setting == null || from == null) {
      throw const FormatException(
        '"pack" and "key" must name a choice from '
        'the web',
      );
    }
    final typed = (query ?? '').trim();
    if (typed.length < from.leastTyped) {
      throw FormatException('"q" must be at least ${from.leastTyped} long');
    }
    final feed = await requestOf(
      _ref,
      (id: '$packId:$key', source: _asking(from.source.inPack(packId!), typed)),
      reactive: false,
      needsAllSettings: false,
    );
    final answer = await _ref.read(feedFetcherProvider)(feed);
    return [for (final row in from.source.rowsOf(answer)) ?from.hitFrom(row)];
  }

  /// [source] with what was typed put in its address.
  Source _asking(Source source, String typed) => source.withAddress(
    '${Template.parse(source.address).fill(const {'query'}, (root) => root == 'query' ? Uri.encodeQueryComponent(typed) : null)}',
  );
}

final packServiceProvider = Provider<PackService>(PackService.new);
