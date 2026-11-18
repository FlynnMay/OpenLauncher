import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/source_request.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';
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

  /// Keeps [value], one the setting accepts, as the secret setting [key] of
  /// [packId]. No value (a delete) clears it; a blank one is refused, so a
  /// secret is only ever cleared on purpose.
  Future<void> setSecret(String? packId, String? path, Object? value) async {
    final leaf = fieldOf(await _ref.read(packsProvider.future), packId, path);
    if (leaf == null || !leaf.secret) {
      throw const FormatException('"pack" and "key" must name a secret');
    }
    if (value != null && FieldSpec.isBlank(value)) {
      throw const FormatException('A secret cannot be blank; delete it');
    }
    if (value != null && !leaf.spec.accepts(value)) {
      throw FormatException('"value" does not fit $path');
    }
    await _ref
        .read(packSecretsProvider.notifier)
        .set(
          packId!,
          leaf.path,
          value == null ? '' : FieldSpec.storedAs(value),
        );
  }

  /// The options the choice at [path] of [packId] finds for [query], each as
  /// it is listed, and the value choosing it keeps.
  Future<List<FieldHit>> options(
    String? packId,
    String? path,
    String? query,
  ) async {
    final leaf = fieldOf(await _ref.read(packsProvider.future), packId, path);
    return _search(leaf?.spec, packId, '$packId:$path', query);
  }

  /// The same for the premade field [fieldId], `system:location`, which a
  /// variable of a card may be.
  Future<List<FieldHit>> optionsOfField(String? fieldId, String? query) async {
    final packId = fieldId?.split(':').first;
    final name = fieldId?.split(':').last;
    final packs = await _ref.read(packsProvider.future);
    final spec = packs
        .where((pack) => pack.id == packId)
        .firstOrNull
        ?.fields[name];
    return _search(spec, packId, '$fieldId', query);
  }

  Future<List<FieldHit>> _search(
    FieldSpec? spec,
    String? packId,
    String id,
    String? query,
  ) async {
    final from = spec?.from;
    if (from == null) {
      throw const FormatException('The field must be a choice from the web');
    }
    final typed = (query ?? '').trim();
    if (typed.length < from.leastTyped) {
      throw FormatException('"q" must be at least ${from.leastTyped} long');
    }
    final feed = await requestOf(
      _ref,
      (id: id, source: _asking(from.source.inPack(packId!), typed)),
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
