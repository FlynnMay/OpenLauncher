import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

typedef _Binding = ({String itemId, String provider});

final _widgetIdProvider = FutureProvider.family<int?, _Binding>(
  (ref, binding) => ref
      .watch(launcherPlatformProvider)
      .bindWidget(binding.itemId, binding.provider),
);

/// Tells the device which app widgets the layout still uses, so it can free
/// the rest.
final widgetCleanupProvider = Provider<void>((ref) {
  ref.listen(configProvider, (_, next) {
    final layout = next.value?.layout;
    if (layout == null) return;
    ref.read(launcherPlatformProvider).pruneWidgets([
      for (final item in layout.items)
        if (item.has(appWidgetModule.name)) item.id,
    ]);
  }, fireImmediately: true);
});

/// A widget from an installed app, drawn by Android inside the layout. It is
/// shown but cannot be focused with the remote.
///
/// Options: `provider`, the id of the `WidgetProvider` to show.
class AppWidgetView extends ConsumerWidget {
  const AppWidgetView({super.key, required this.item});

  final Node item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget note(String text) => Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
    final provider = item.values(appWidgetModule.name)?['provider'];
    if (provider is! String) return note('Choose a widget on the web page');
    final id = ref.watch(
      _widgetIdProvider((itemId: item.id, provider: provider)),
    );
    return switch (id) {
      AsyncData(:final value?)
          when !kIsWeb && defaultTargetPlatform == TargetPlatform.android =>
        ExcludeFocus(
          child: IgnorePointer(
            child: AndroidView(
              key: ValueKey(value),
              viewType: 'openlauncher/appwidget',
              creationParams: value,
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        ),
      AsyncLoading() => const SizedBox.shrink(),
      _ => note('This widget cannot be shown.\nThe TV does not allow it.'),
    };
  }
}
