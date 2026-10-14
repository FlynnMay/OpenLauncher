import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/server/auth.dart';
import 'package:openlauncher/server/config_server.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Re-read each time the dialog opens.
final _configUrlProvider = FutureProvider.autoDispose<Uri?>((ref) async {
  final server = await ref.watch(configServerProvider.future);
  return server?.url();
});

/// Shows the editor's address, the pairing code and a QR code that carries
/// the code so a scan pairs on its own.
class RemoteConfigDialog extends ConsumerWidget {
  const RemoteConfigDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const RemoteConfigDialog());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(_configUrlProvider);
    return AlertDialog(
      title: const Text('Customise from your phone'),
      content: switch (url) {
        AsyncData(value: final url?) => _Pairing(url: url),
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

/// The QR, address and live pairing code. Pairing is open only while this
/// is on screen.
class _Pairing extends ConsumerStatefulWidget {
  const _Pairing({required this.url});

  final Uri url;

  @override
  ConsumerState<_Pairing> createState() => _PairingState();
}

class _PairingState extends ConsumerState<_Pairing> {
  late final PairingCode _pairing = ref.read(pairingProvider)..open();

  @override
  void dispose() {
    _pairing.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: _pairing.listenable,
      builder: (context, code, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: _pairing.link(widget.url).toString(),
              size: 180,
            ),
          ),
          const SizedBox(height: 16),
          Text('${widget.url}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Pairing code', style: theme.textTheme.bodySmall),
          Text(
            // Shown in two groups of three, easier to read.
            code == null ? '' : '${code.substring(0, 3)} ${code.substring(3)}',
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 4),
          ),
          const SizedBox(height: 8),
          Text(
            'On a device on the same network, scan the code or go to the\n'
            'address and enter the pairing code.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
