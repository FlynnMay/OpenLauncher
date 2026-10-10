import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/config_server.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The address of the config page, re-read each time the dialog opens.
final _configUrlProvider = FutureProvider.autoDispose<Uri?>((ref) async {
  final server = await ref.watch(configServerProvider.future);
  return server?.url();
});

/// Shows how to open the config page from a phone or computer.
class RemoteConfigDialog extends ConsumerWidget {
  const RemoteConfigDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const RemoteConfigDialog());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = ref.watch(_configUrlProvider);
    return AlertDialog(
      title: const Text('Customise from your phone'),
      content: switch (url) {
        AsyncData(value: final url?) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: url.toString(), size: 180),
            ),
            const SizedBox(height: 16),
            Text('$url', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Scan the code or type the address on a device\n'
              'connected to the same network.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        AsyncData() => const Text(
          'The config page is unavailable. Check that the TV is connected '
          'to your network.',
        ),
        AsyncError(:final error) => Text('Could not start: $error'),
        _ => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
