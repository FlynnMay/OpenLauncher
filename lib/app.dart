import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'server/config_server.dart';

class OpenLauncherApp extends ConsumerWidget {
  const OpenLauncherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the config web server running for as long as the app is.
    ref.watch(configServerProvider);
    return MaterialApp(
      title: 'OpenLauncher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.indigo, brightness: .dark),
      ),
      home: const HomeScreen(),
    );
  }
}
