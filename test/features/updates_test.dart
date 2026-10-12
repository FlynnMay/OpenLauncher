import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

import '../support/updates.dart';

void main() {
  late FakeUpdateSource source;
  late FakeLauncherPlatform platform;
  late MemoryConfigStore store;

  setUp(() {
    source = FakeUpdateSource(release(later, notes: 'Faster folders.'));
    platform = FakeLauncherPlatform(const [], const []);
    store = MemoryConfigStore();
  });

  Future<void> start(WidgetTester tester, {UpdateMode? mode}) async {
    if (mode != null) {
      store.config = LauncherConfig(updates: UpdateOptions(mode: mode));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          launcherPlatformProvider.overrideWithValue(platform),
          configServerProvider.overrideWith((ref) => null),
          updateSourceProvider.overrideWithValue(source),
          nowProvider.overrideWithValue(() => tester.binding.clock.now()),
        ],
        child: const OpenLauncherApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('checks soon after starting and tells of a release once', (
    tester,
  ) async {
    await start(tester);
    expect(source.checks, 0);
    await tester.pump(firstUpdateCheck);
    await tester.pumpAndSettle();
    expect(source.checks, 1);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('Version $later'), findsOneWidget);
    // Nothing is installed unasked.
    expect(platform.installed, isEmpty);

    // The next day's check finds the same release: no second toast.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    await tester.pump(updateCheckEvery);
    await tester.pumpAndSettle();
    expect(source.checks, 2);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('does not check when updates are off', (tester) async {
    await start(tester, mode: UpdateMode.off);
    await tester.pump(firstUpdateCheck * 2);
    await tester.pumpAndSettle();
    expect(source.checks, 0);
  });

  testWidgets('set to install, waits until the TV has been left alone', (
    tester,
  ) async {
    await start(tester, mode: UpdateMode.auto);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(firstUpdateCheck);
    await tester.pumpAndSettle();
    expect(source.checks, 1);
    // It installs itself, so nothing is announced.
    expect(find.text('Update available'), findsNothing);

    // A key pressed four minutes in starts the wait again.
    await tester.pump(const Duration(minutes: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(minutes: 4));
    expect(platform.installed, isEmpty);
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(platform.installed, ['/cache/update.apk']);

    // It failed here; it is not tried again each minute.
    await tester.pump(const Duration(minutes: 10));
    expect(platform.installed, hasLength(1));
  });

  testWidgets('set to install, does not while another app is in front', (
    tester,
  ) async {
    await start(tester, mode: UpdateMode.auto);
    void pass(List<AppLifecycleState> through) =>
        through.forEach(tester.binding.handleAppLifecycleStateChanged);
    pass(const [.resumed, .inactive, .hidden, .paused]);
    await tester.pump(firstUpdateCheck);
    await tester.pump(const Duration(minutes: 10));
    expect(source.checks, 1);
    expect(platform.installed, isEmpty);
    // Back on the launcher, and left alone.
    pass(const [.hidden, .inactive, .resumed]);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(platform.installed, hasLength(1));
  });

  testWidgets('Settings checks, then offers the release and installs it', (
    tester,
  ) async {
    platform.homeButtonEnabled = false;
    await start(tester, mode: UpdateMode.off);
    await tester.tap(find.text('Set as Home'));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Updates');
    await tester.ensureVisible(tile);
    expect(find.text('Version $appVersion'), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(source.checks, 1);
    expect(
      find.text('Version $later is available. Press to install.'),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('OpenLauncher $later'), findsOneWidget);
    expect(find.text('Faster folders.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(platform.installed, isEmpty);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(platform.installed, ['/cache/update.apk']);
    // The fake TV refused; the tile says why.
    expect(find.text('There is no TV here.'), findsOneWidget);
  });

  testWidgets('the editor sets what is done, checks and installs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          launcherPlatformProvider.overrideWithValue(platform),
          updateSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: UpdateSettings())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    expect(find.text('Version $appVersion'), findsOneWidget);
    expect(find.text('Install'), findsNothing);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Version $later is available'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();
    expect(platform.installed, ['/cache/update.apk']);

    // Automatic updates: Off.
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(store.config.updates.mode, UpdateMode.off);
  });
}
