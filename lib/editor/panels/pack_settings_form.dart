import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// What [pack] asks the user for. Plain values are saved in the config; a
/// secret goes to the TV on its own and is never shown again.
class PackSettingsForm extends ConsumerWidget {
  const PackSettingsForm(this.pack, {super.key});

  final Pack pack;

  static Field _field(PackSetting setting) => Field(
    setting.key,
    setting.label,
    switch (setting.type) {
      PackSettingType.number => FieldKind.number,
      PackSettingType.tick => FieldKind.toggle,
      PackSettingType.choice => FieldKind.choice,
      _ => FieldKind.text,
    },
    choices: setting.choices,
    min: -1000000,
    max: 1000000,
  );

  /// Whether a required setting of [pack] still has no value.
  static bool missing(
    Pack pack,
    Map<String, Object?> values,
    Set<String> secrets,
  ) => pack.settings.any(
    (setting) =>
        setting.required &&
        (setting.secret
            ? !secrets.contains(setting.key)
            : values[setting.key] == null),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final values = config.packSettings[pack.id] ?? const {};
    final secrets = ref.watch(tvStateProvider).value?.secrets[pack.id] ?? {};
    final plain = [
      for (final setting in pack.settings)
        if (!setting.secret) setting,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...optionFields(
            options: [for (final setting in plain) _field(setting)],
            values: values,
            onChanged: (next) => changeConfig(
              context,
              ref,
              (controller) => controller.patch({
                'packSettings': {...config.packSettings, pack.id: next},
              }),
            ),
          ),
          for (final setting in pack.settings)
            if (setting.secret)
              _SecretField(
                pack: pack,
                setting: setting,
                isSet: secrets.contains(setting.key),
              ),
        ],
      ),
    );
  }
}

class _SecretField extends ConsumerStatefulWidget {
  const _SecretField({
    required this.pack,
    required this.setting,
    required this.isSet,
  });

  final Pack pack;
  final PackSetting setting;
  final bool isSet;

  @override
  ConsumerState<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends ConsumerState<_SecretField> with Busy {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _keep(String value) => whileBusy(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(tvApiProvider)
          .setSecret(widget.pack.id, widget.setting.key, value);
      _text.clear();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      spacing: 8,
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.setting.label,
              helperText: widget.isSet
                  ? 'Set. Type to replace it.'
                  : 'Not set.',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: busy || _text.text.isEmpty ? null : _keep,
          ),
        ),
        FilledButton.tonal(
          onPressed: busy ? null : () => _keep(_text.text),
          child: const Text('Save'),
        ),
        if (widget.isSet)
          IconButton(
            tooltip: 'Clear',
            onPressed: busy ? null : () => _keep(''),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
  );
}
