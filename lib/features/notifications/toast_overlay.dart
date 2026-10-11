import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

final notificationsProvider = StreamProvider<AppNotification>(
  (ref) => ref.watch(launcherPlatformProvider).notifications,
);

/// Shows other apps' notifications one at a time in a corner, as configured.
class ToastOverlay extends ConsumerStatefulWidget {
  const ToastOverlay({super.key});

  @override
  ConsumerState<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends ConsumerState<ToastOverlay> {
  /// Beyond this the oldest are dropped.
  static const _maxWaiting = 5;

  final _waiting = Queue<AppNotification>();
  AppNotification? _showing;
  Timer? _timer;

  ToastOptions get _options =>
      ref.read(configProvider).value?.toasts ?? const ToastOptions();

  void _add(AppNotification notification) {
    if (!_options.enabled) return;
    _waiting.add(notification);
    while (_waiting.length > _maxWaiting) {
      _waiting.removeFirst();
    }
    if (_showing == null) _next();
  }

  void _next() {
    _timer?.cancel();
    setState(() => _showing = _waiting.isEmpty ? null : _waiting.removeFirst());
    if (_showing != null) {
      _timer = Timer(Duration(seconds: _options.seconds), _next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationsProvider, (_, next) {
      if (next case AsyncData(:final value)) _add(value);
    });
    final position =
        ref.watch(configProvider).value?.toasts.position ??
        ToastPosition.topRight;
    final showing = _showing;
    return IgnorePointer(
      child: Align(
        alignment: switch (position) {
          ToastPosition.topLeft => Alignment.topLeft,
          ToastPosition.topRight => Alignment.topRight,
          ToastPosition.bottomLeft => Alignment.bottomLeft,
          ToastPosition.bottomRight => Alignment.bottomRight,
        },
        child: Padding(
          // Inside the TV's overscan margin.
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showing == null
                ? const SizedBox.shrink()
                : _Toast(key: ObjectKey(showing), notification: showing),
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = notification.title, text = notification.text;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xF21A1C23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.appLabel,
            style: theme.labelSmall?.copyWith(color: Colors.white60),
          ),
          if (title != null && title.isNotEmpty)
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
          if (text != null && text.isNotEmpty)
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall?.copyWith(color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
