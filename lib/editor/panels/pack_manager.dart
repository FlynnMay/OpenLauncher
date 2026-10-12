import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/panels/media_manager.dart';
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
    if (file != null) await ref.read(tvApiProvider).installPack(file);
  });

  Future<void> _remove(Pack pack) async {
    final sure = await confirm(
      context,
      'Remove "${pack.name}"?',
      'It comes off the TV. It can be installed again from its file.',
      'Remove',
    );
    if (!sure) return;
    await whileBusy(() => ref.read(tvApiProvider).removePack(pack.id));
  }

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

class _PackRow extends ConsumerWidget {
  const _PackRow({required this.pack, required this.uses, this.onRemove});

  final Pack pack;

  /// How many icons of it the config names.
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
        ? 'In use: $uses ${uses == 1 ? 'icon' : 'icons'}'
        : null;
    return ListTile(
      title: Text(pack.name),
      subtitle: Text(
        [
          if (pack.version.isNotEmpty) 'Version ${pack.version}',
          if (pack.author.isNotEmpty) pack.author,
          if (pack.licence.isNotEmpty) pack.licence,
          if (icons > 0) '$icons icons',
          MediaManager.sizeOf(pack.bytes),
          ?kept,
        ].join('  ·  '),
      ),
      trailing: IconButton(
        tooltip: kept ?? 'Remove',
        onPressed: kept == null ? onRemove : null,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
