import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';

/// Answers an `os://` query as plain rows, pictures as file paths. [watch]
/// reads it again when the device reports a change.
typedef OsQuery = Future<List<Map<String, Object?>>> Function(
  Ref ref,
  bool watch,
);

/// What `os://<name>` answers. A new one is one entry here; only the
/// launcher reads these, never the network.
final Map<String, OsQuery> osSources = {
  'apps': (ref, watch) async => [
    for (final app in await _read(ref, installedAppsProvider.future, watch))
      {
        'package': app.packageName,
        'label': app.label,
        'icon': app.iconPath,
        'banner': app.isBanner,
      },
  ],
  'inputs': (ref, watch) async => [
    for (final input in await _read(ref, tvInputsProvider.future, watch))
      {'id': input.id, 'label': input.label, 'kind': input.kind.name},
  ],
};

T _read<T>(Ref ref, ProviderListenable<T> provider, bool watch) =>
    watch ? ref.watch(provider) : ref.read(provider);
