import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// What [pack] asks the user for. Plain values are saved in the config; a
/// secret goes to the TV on its own and is never shown again.
class PackSettingsForm extends ConsumerWidget {
  const PackSettingsForm(this.pack, {super.key});

  final Pack pack;

  /// The labels of the required fields of [pack] that still have no value.
  static List<String> missing(
    Pack pack,
    Map<String, Object?> values,
    Set<String> secrets,
  ) => pack.missing(values, secrets);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final values = config.packSettings[pack.id] ?? const {};
    final secrets = ref.watch(tvStateProvider).value?.secrets[pack.id] ?? {};
    final api = ref.read(tvApiProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: optionFields(
          options: [
            for (final setting in pack.settings)
              setting.spec.toField(
                setting.key,
                findAt: (path, text) => api.fieldOptions(pack.id, path, text),
                secretAt: (path) => FieldSecret(
                  isSet: secrets.contains(path),
                  replace: (value) => api.setSecret(pack.id, path, value),
                  clear: () => api.clearSecret(pack.id, path),
                ),
              ),
          ],
          values: values,
          onChanged: (next) => setSettings(context, ref, {
            'packSettings': {...config.packSettings, pack.id: next},
          }),
        ),
      ),
    );
  }
}
