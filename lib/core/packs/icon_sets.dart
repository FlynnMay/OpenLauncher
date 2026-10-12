import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/icon_set.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_store.dart';

/// Reads a file of an installed pack; null if it has none at [path].
typedef PackReader = Future<Uint8List?> Function(Pack pack, String path);

/// Every installed pack. The editor's come from the TV.
final packsProvider = FutureProvider<List<Pack>>((ref) {
  final store = ref.watch(packStoreProvider);
  store.addListener(ref.invalidateSelf);
  ref.onDispose(() => store.removeListener(ref.invalidateSelf));
  return store.list();
});

final packReaderProvider = Provider<PackReader>(
  (ref) => ref.watch(packStoreProvider).read,
);

IconSet? _readIndex((String, Uint8List) index) =>
    IconSet.fromJson(index.$1, jsonDecode(utf8.decode(index.$2)));

/// Font families already given to the engine, which keeps them for good.
final _families = <String>{};

/// The icon set called [id] with its font loaded; null if no pack has it.
/// Read again only when its pack changes.
final iconSetProvider = FutureProvider.family<IconSet?, String>((
  ref,
  id,
) async {
  final pack = await ref.watch(
    packsProvider.selectAsync(
      (packs) => packs.where((pack) => pack.iconSets.contains(id)).firstOrNull,
    ),
  );
  if (pack == null) return null;
  final read = ref.watch(packReaderProvider);
  final index = await read(pack, 'icons/$id.json');
  if (index == null) return null;
  // Thousands of icons: read off the UI thread, where there is another.
  final set = await compute(_readIndex, (id, index));
  if (set == null) return null;
  // A changed pack gets a new family: a loaded font cannot be replaced.
  final family = 'pack/${pack.id}/${set.font}/${pack.version}/${pack.bytes}';
  if (!_families.contains(family)) {
    final font = await read(pack, 'fonts/${set.font}');
    if (font == null) return null;
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    _families.add(family);
  }
  return set.loadedAs(family);
});

/// Every icon set of every pack, loaded.
final iconSetsProvider = FutureProvider<List<IconSet>>((ref) async {
  final ids = await ref.watch(
    packsProvider.selectAsync(
      (packs) => [for (final pack in packs) ...pack.iconSets].join(' '),
    ),
  );
  return [
    for (final id in ids.split(' '))
      if (id.isNotEmpty) ?await ref.watch(iconSetProvider(id).future),
  ];
});
