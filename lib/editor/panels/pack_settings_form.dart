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

  static Field _field(PackSetting setting) => Field(
    setting.key,
    labelOf(setting),
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

  /// The labels of the required settings of [pack] that still have no value.
  static List<String> missing(
    Pack pack,
    Map<String, Object?> values,
    Set<String> secrets,
  ) => [
    for (final setting in pack.settings)
      if (setting.required &&
          (setting.secret
              ? !secrets.contains(setting.key)
              : values[setting.key] == null))
        setting.label,
  ];

  /// A required setting is marked.
  static String labelOf(PackSetting setting) =>
      setting.required ? '${setting.label} *' : setting.label;

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
            onChanged: (next) => setSettings(context, ref, {
              'packSettings': {...config.packSettings, pack.id: next},
            }),
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

  /// Replaces the secret with what was typed; never with nothing.
  Future<void> _replace() => whileBusy(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(tvApiProvider)
          .setSecret(widget.pack.id, widget.setting.key, _text.text);
      _text.clear();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  });

  /// Forgets the secret, once the user has said so.
  Future<void> _clear() async {
    final sure = await confirm(
      context,
      'Clear ${widget.setting.label}?',
      'It is forgotten on the TV. The pack cannot reach what it signs into '
          'until a new one is saved.',
      'Clear',
    );
    if (!sure || !mounted) return;
    await whileBusy(
      () => ref
          .read(tvApiProvider)
          .clearSecret(widget.pack.id, widget.setting.key),
    );
  }

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
              labelText: PackSettingsForm.labelOf(widget.setting),
              // A kept secret shows as dots and stays until cleared.
              hintText: widget.isSet ? '••••••••••••••••' : 'Not set',
              helperText: widget.isSet
                  ? 'Saved on the TV. Type a new one to replace it.'
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: widget.isSet
                  ? IconButton(
                      tooltip: 'Clear',
                      onPressed: busy ? null : _clear,
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: busy || _text.text.isEmpty ? null : (_) => _replace(),
          ),
        ),
        FilledButton.tonal(
          onPressed: busy || _text.text.isEmpty ? null : _replace,
          child: Text(widget.isSet ? 'Replace' : 'Save'),
        ),
      ],
    ),
  );
}
