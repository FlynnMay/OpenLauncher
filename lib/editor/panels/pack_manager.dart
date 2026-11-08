import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/panels/media_manager.dart';
import 'package:openlauncher/editor/panels/pack_settings_form.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// Opens the pack manager.
class PacksButton extends StatelessWidget {
  const PacksButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: PackManager.title,
    onPressed: () => PackManager.show(context),
    icon: const Icon(PackManager.icon),
  );
}

/// The packs installed on the TV: what each holds, installing one from a
/// `.zip`, and removing one nothing uses.
class PackManager extends ConsumerStatefulWidget {
  const PackManager({super.key});

  static const title = 'Packs';
  static const icon = Icons.extension_outlined;

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 640, height: 520, child: PackManager()),
    ),
  );

  @override
  ConsumerState<PackManager> createState() => _PackManagerState();
}

class _PackManagerState extends ConsumerState<PackManager>
    with Busy<PackManager> {
  Future<void> _install() => whileBusy(() async {
    final file = await pickFile(accept: '.zip,application/zip');
    if (file == null) return;
    final api = ref.read(tvApiProvider);
    final change = await api.checkPack(file);
    if (!mounted) return;
    final asked = _askAboutReplacing(change);
    if (asked != null &&
        !await confirm(context, asked.$1, asked.$2, asked.$3)) {
      return;
    }
    await api.installPack(file);
  });

  /// What to ask before a pack replaces one with its id: title, body and the
  /// button; null for a pack that is new.
  (String, String, String)? _askAboutReplacing(Map<Object?, Object?> change) {
    final name = change['name'];
    final was = change['installedVersion'];
    final now = change['version'];
    return switch (change['change']) {
      'same' => (
        '"$name" is already installed',
        'Version $now is on the TV. Install this file over it?',
        'Replace',
      ),
      'older' => (
        'Install an older "$name"?',
        'Version $was is on the TV; this file is version $now. '
            'Installing it is a downgrade.',
        'Downgrade',
      ),
      'newer' => (
        'Update "$name"?',
        'Version $was is on the TV; this file is version $now.',
        'Update',
      ),
      'different' => (
        'Replace "$name"?',
        'It is on the TV (version "$was"). This file is version "$now", '
            'which cannot be compared with it.',
        'Replace',
      ),
      _ => null,
    };
  }

  /// Removes [pack], and with it the settings the user gave it if asked.
  Future<void> _remove(Pack pack) async {
    final kept = ref.read(configProvider).value?.packSettings[pack.id];
    final answer = await _askAboutRemoving(pack, hasSettings: kept != null);
    if (answer == null) return;
    await whileBusy(() async {
      await ref.read(tvApiProvider).removePack(pack.id);
      if (answer == _Removal.packAndSettings && mounted) {
        await _forgetSettingsOf(pack.id);
      }
    });
  }

  Future<_Removal?> _askAboutRemoving(
    Pack pack, {
    required bool hasSettings,
  }) => showDialog<_Removal>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove "${pack.name}"?'),
      content: Text(
        hasSettings
            ? 'It comes off the TV. Its settings stay unless you delete them '
                  'too, so a pack installed again finds them. (A secret is '
                  'always forgotten.)'
            : 'It comes off the TV. It can be installed again from its file.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (hasSettings)
          TextButton(
            onPressed: () => Navigator.pop(context, _Removal.packOnly),
            child: const Text('Remove pack only'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            hasSettings ? _Removal.packAndSettings : _Removal.packOnly,
          ),
          child: Text(hasSettings ? 'Remove pack and settings' : 'Remove'),
        ),
      ],
    ),
  );

  Future<void> _forgetSettingsOf(String packId) async {
    final saved = ref.read(configProvider).value?.packSettings ?? const {};
    await setSettings(context, ref, {
      'packSettings': {
        for (final MapEntry(:key, :value) in saved.entries)
          if (key != packId) key: value,
      },
    });
  }

  /// Pack ids the config has settings for that are not installed.
  List<String> _leftBehind(List<Pack> installed) => [
    for (final id
        in ref.watch(configProvider).value?.packSettings.keys ?? <String>[])
      if (!installed.any((pack) => pack.id == id)) id,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packs = ref.watch(packsProvider);
    final saved = ref.watch(configProvider).value?.toJson();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  PackManager.title,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : _install,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Install'),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (packs) {
            AsyncValue(:final error?) when !packs.hasValue => Center(
              child: Text('$error'.replaceFirst(RegExp(r'^Exception: '), '')),
            ),
            AsyncValue(:final value?) when value.isNotEmpty => ListView(
              children: [
                for (final pack in value)
                  _PackRow(
                    pack: pack,
                    uses: pack.usesIn(saved),
                    onRemove: busy ? null : () => _remove(pack),
                  ),
                for (final left in _leftBehind(value))
                  ListTile(
                    leading: const Icon(Icons.history_toggle_off_outlined),
                    title: Text('Settings left by "$left"'),
                    subtitle: const Text(
                      'That pack is not installed. They return if it is.',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete these settings',
                      onPressed: busy
                          ? null
                          : () => whileBusy(() => _forgetSettingsOf(left)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
            _ when !packs.hasValue => const Center(
              child: CircularProgressIndicator(),
            ),
            _ => const Center(child: Text('No packs are installed.')),
          },
        ),
      ],
    );
  }
}

enum _Removal { packOnly, packAndSettings }

class _PackRow extends ConsumerWidget {
  const _PackRow({required this.pack, required this.uses, this.onRemove});

  final Pack pack;

  /// How many times the config names something of it.
  final int uses;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = [
      for (final set in pack.iconSets)
        ref.watch(iconSetProvider(set)).value?.icons.length ?? 0,
    ].fold(0, (sum, count) => sum + count);
    final kept = pack.builtIn
        ? 'Built in'
        : uses > 0
        ? 'In use in $uses ${uses == 1 ? 'place' : 'places'}'
        : null;
    final config = ref.watch(configProvider).value;
    final needs = PackSettingsForm.missing(
      pack,
      config?.packSettings[pack.id] ?? const {},
      ref.watch(tvStateProvider).value?.secrets[pack.id] ?? {},
    );
    final tile = ListTile(
      title: Text(pack.name),
      subtitle: Text(
        [
          if (pack.version.isNotEmpty) 'Version ${pack.version}',
          if (pack.author.isNotEmpty) pack.author,
          if (pack.licence.isNotEmpty) pack.licence,
          if (icons > 0) '$icons icons',
          MediaManager.sizeOf(pack.bytes),
          ?kept,
          if (pack.requires.isNotEmpty) 'Needs ${pack.requires.join(', ')}',
          if (pack.source.isNotEmpty) pack.source,
          if (needs.isNotEmpty) 'Still needs: ${needs.join(', ')}',
        ].join('  ·  '),
      ),
      trailing: IconButton(
        tooltip: kept ?? 'Remove',
        onPressed: kept == null ? onRemove : null,
        icon: const Icon(Icons.delete_outline),
      ),
    );
    if (pack.settings.isEmpty) return tile;
    return ExpansionTile(
      title: Text(pack.name),
      subtitle: tile.subtitle,
      trailing: tile.trailing,
      children: [PackSettingsForm(pack)],
    );
  }
}
