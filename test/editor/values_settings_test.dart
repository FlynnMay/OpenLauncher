import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

void main() {
  testWidgets("the user's entities are made in the form, actions and all", (
    tester,
  ) async {
    var entities = <Entity>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform(const [], const []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => ValuesSettings(
                  entities: entities,
                  place: null,
                  onEntities: (next) => setState(() => entities = next),
                  onPlace: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> name(String add, String name) async {
      await tester.ensureVisible(find.text(add));
      await tester.tap(find.text(add));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        name,
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Values'));
    await tester.pumpAndSettle();
    await name('Add entity', 'Plex Shortcut');
    // Its id comes from its name; until told otherwise it asks an address.
    expect(entities.single.id, 'plex-shortcut');
    expect(entities.single.label, 'Plex Shortcut');
    expect(entities.single.feed?.from, httpFeed);

    await name('Add action', 'open');
    // The first operation there is, with nothing bound: the act says it all.
    expect(entities.single.actions, const {
      'open': EntityAction(run: 'os://apps/launch', args: {'package': []}),
    });
    await tester.enterText(
      find.widgetWithText(TextField, 'package'),
      'com.plexapp',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(entities.single.actions, const {
      'open': EntityAction(
        run: 'os://apps/launch',
        bound: {'package': 'com.plexapp'},
      ),
    });

    // Timers of what it reads end with it.
    await tester.pumpWidget(const SizedBox());
  });
}
