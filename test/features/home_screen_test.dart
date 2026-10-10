import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

void main() {
  testWidgets('shows app cards and launches with the D-pad', (tester) async {
    final platform = FakeLauncherPlatform([
      InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
      InstalledApp(packageName: 'pkg.b', label: 'Beta', isBanner: false),
    ], []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(platform),
          configServerProvider.overrideWith((ref) => null),
        ],
        child: const OpenLauncherApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);

    // First card has focus on start; D-pad centre launches it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(platform.launched, ['pkg.a']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(platform.launched, ['pkg.a', 'pkg.b']);
  });

  group('settings', () {
    late FakeLauncherPlatform platform;

    Future<void> openSettings(WidgetTester tester) async {
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
      ], [])..homeButtonEnabled = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configStoreProvider.overrideWithValue(MemoryConfigStore()),
            launcherPlatformProvider.overrideWithValue(platform),
            configServerProvider.overrideWith((ref) => null),
          ],
          child: const OpenLauncherApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set as Home'));
      await tester.pumpAndSettle();
    }

    testWidgets('automatic setup turns the Home button on', (tester) async {
      await openSettings(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Set up automatically'));
      await tester.pumpAndSettle();
      expect(find.text('All set'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Once set up, the switch works directly.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(platform.homeButtonEnabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // Back on the home screen the prompt is offered again.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Set as Home'), findsOneWidget);
    });

    testWidgets('explains what to do when debugging is off', (tester) async {
      await openSettings(tester);
      platform.setupOutcome = SetupOutcome.adbUnavailable;

      // Turning the switch on before setup runs setup.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('USB debugging is off'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(platform.homeButtonEnabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('re-checks the Home button when the app resumes', (
      tester,
    ) async {
      await openSettings(tester);
      // The user switches the service on in the TV's own settings.
      platform.homeButtonEnabled = true;
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });
}
