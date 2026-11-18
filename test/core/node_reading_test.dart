import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher_domain/layout/layout.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/values/template.dart';

import '../support/packs.dart';

void main() {
  // main
  //  ├─ card        (variables: title public, tint protected, key private)
  //  │   ├─ label   (child, variable text)
  //  │   └─ icon    (child, public, style module public)
  //  └─ other
  Node label() => drawn(
    'label',
    textModule.name,
    vars: const {'text': Variable('Kitchen', access: NodeAccess.public)},
  );
  Node icon() =>
      drawn('icon', textModule.name, style: const {'padding': 12}).copyWith(
        access: NodeAccess.public,
        moduleAccess: {'style': NodeAccess.public},
      );
  Node card() => drawn(
    'card',
    textModule.name,
    style: const {'padding': 3},
    vars: const {
      'title': Variable('Lights', access: NodeAccess.public),
      'tint': Variable('red'),
      'key': Variable('s', access: NodeAccess.private),
    },
  ).copyWith(children: [label(), icon()]);

  ProviderContainer container() {
    final layout = Layout(
      inbox: 'main',
      screens: [
        Screen(
          id: Layout.homeId,
          root: Node.layout(
            id: 'main',
            children: [card(), drawn('other', textModule.name)],
          ),
        ),
      ],
    );
    final c = ProviderContainer(
      overrides: [
        ...launcherOverrides,
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(layout: layout)),
        ),
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(const [], const []),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<String> reads(String template, {String? as}) async {
    final c = container();
    await c.read(entitiesProvider.future);
    final scope = {readerKey: ?as};
    // Providers are kept alive by a listener while read.
    final roots = Template.parse(template).roots;
    final holds = [
      for (final root in roots)
        c.listen(nodeValueProvider((root: root, reader: as)), (_, _) {}),
    ];
    addTearDown(() {
      for (final hold in holds) {
        hold.close();
      }
    });
    return valueText(readTemplate(c.read, template, scope));
  }

  test('a plain id reads as it always did: what is public', () async {
    expect(
      await reads('{{card.title}}|{{card.tint}}|{{card.key}}'),
      'Lights||',
    );
  });

  test('a child is reached by its parent, when its level lets', () async {
    // The icon is public: anyone. The label is protected: the card and
    // what is under it.
    expect(await reads('{{card/icon#style.padding}}'), '12');
    expect(await reads('{{card/label.text}}'), '');
    expect(await reads('{{card/label.text}}', as: 'other'), '');
    expect(await reads('{{card/label.text}}', as: 'card'), 'Kitchen');
    expect(await reads('{{card/label.text}}', as: 'card/icon'), 'Kitchen');
  });

  test('a module is private unless its node says', () async {
    expect(await reads('{{card/icon#style.padding}}', as: 'other'), '12');
    expect(await reads('{{card#style.padding}}', as: 'other'), '');
    expect(await reads('{{card#style.padding}}', as: 'card'), '3');
  });

  test('self, parent and root start from the node that reads', () async {
    expect(await reads('{{self/label.text}}', as: 'card'), 'Kitchen');
    expect(await reads('{{parent/card.title}}', as: 'other'), 'Lights');
    expect(await reads('{{parent.title}}', as: 'label'), 'Lights');
    expect(await reads('{{root/card.title}}', as: 'other'), 'Lights');
    expect(await reads('{{parent.title}}'), '');
  });

  test('a node reads its own and what is protected from under it', () async {
    expect(await reads('{{self.tint}}', as: 'card'), 'red');
    expect(await reads('{{parent.tint}}', as: 'label'), 'red');
    expect(await reads('{{parent.tint}}', as: 'other'), '');
    expect(await reads('{{parent.key}}', as: 'label'), '');
  });
}
