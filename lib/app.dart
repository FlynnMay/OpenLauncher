import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/notifications/toast_overlay.dart';
import 'package:openlauncher/features/widgets/app_widget.dart';
import 'package:openlauncher/server/config_server.dart';

class OpenLauncherApp extends ConsumerWidget {
  const OpenLauncherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the config web server running for as long as the app is.
    ref.watch(configServerProvider);
    ref.watch(widgetCleanupProvider);
    return MaterialApp(
      title: 'OpenLauncher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.indigo, brightness: .dark),
      ),
      // Above every screen, so a notification also shows over Settings.
      builder: (context, child) =>
          Stack(children: [?child, const ToastOverlay()]),
      home: const HomeScreen(),
    );
  }
}
