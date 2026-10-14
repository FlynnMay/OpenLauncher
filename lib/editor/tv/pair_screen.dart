import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/tv/auth.dart';
import 'package:openlauncher/editor/tv/tv_api.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(pairingNeededProvider) ? const PairScreen() : child;
}

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: 'Web editor');
  bool _busy = false;
  String? _error;
  bool _triedUrlCode = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tvApiProvider).pair(code, _name.text.trim());
      if (!mounted) return;
      ref.read(pairingNeededProvider.notifier).paired();
      // Reconnect with the new cookie.
      ref.invalidate(tvStateProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A code from the QR link pairs on its own, once.
    final fromUrl = ref.watch(initialPairCodeProvider);
    if (fromUrl != null && fromUrl.length == 6 && !_triedUrlCode) {
      _triedUrlCode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pair(fromUrl));
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pair with your TV',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'On the TV, open "Customise from your phone" and enter the '
                  '6-digit code it shows.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name this device',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 8,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    if (value.length == 6) _pair(value);
                  },
                  onSubmitted: _pair,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : () => _pair(_code.text),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Pair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
