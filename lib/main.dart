import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/registries/source_endpoint_registry.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: sourceEndpointOverrides,
      child: const OpenLauncherApp(),
    ),
  );
}
