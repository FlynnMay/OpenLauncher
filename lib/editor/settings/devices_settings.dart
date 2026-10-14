import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/tv/tv.dart';

final _devicesProvider = FutureProvider.autoDispose<List<_Device>>((ref) async {
  final raw = await ref.watch(tvApiProvider).devices();
  return [
    for (final device in raw)
      (
        id: device['id'] as String? ?? '',
        label: device['label'] as String? ?? 'A device',
        added: DateTime.tryParse('${device['added']}'),
        lastSeen: DateTime.tryParse('${device['lastSeen']}'),
      ),
  ];
});

typedef _Device = ({
  String id,
  String label,
  DateTime? added,
  DateTime? lastSeen,
});

class DevicesSettings extends ConsumerWidget {
  const DevicesSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(_devicesProvider);
    return Section('Trusted devices', [
      switch (devices) {
        AsyncData(:final value) when value.isEmpty => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No devices are paired.'),
        ),
        AsyncData(:final value) => Column(
          children: [for (final device in value) _Row(device)],
        ),
        AsyncError(:final error) => Text('Could not load: $error'),
        _ => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    ]);
  }
}

class _Row extends ConsumerWidget {
  const _Row(this.device);

  final _Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(device.label),
      subtitle: Text(
        'Added ${_when(device.added)} · last seen ${_when(device.lastSeen)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: TextButton(
        onPressed: () async {
          if (!await sureToRemove(
            context,
            device.label,
            'It will need to pair with the TV again.',
          )) {
            return;
          }
          await ref.read(tvApiProvider).revoke(device.id);
          ref.invalidate(_devicesProvider);
        },
        child: const Text('Remove'),
      ),
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return 'unknown';
    final days = DateTime.now().difference(at).inDays;
    return switch (days) {
      0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };
  }
}
