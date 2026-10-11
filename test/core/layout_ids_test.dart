import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

LayoutItem _entity(String id, String ref) =>
    LayoutItem(id: id, kind: ItemKind.prefab, ref: cardPrefabId, source: ref);

void main() {
  test('a name becomes an id that can be read', () {
    expect(slugOf('HDMI 1'), 'hdmi-1');
    expect(slugOf("  Disney+ / Kids' TV "), 'disney-kids-tv');
    expect(slugOf('电视', 'entity'), 'entity');
    expect(freeId('youtube', {'netflix'}), 'youtube');
    expect(freeId('youtube', {'youtube', 'youtube-2'}), 'youtube-3');
  });

  test('new things are named after what they are, without repeating', () {
    final layout = Layout(
      inbox: 'home/root',
      panels: [
        Panel(
          id: 'home',
          root: Pane(
            id: 'home/root',
            items: [
              _entity('youtube', 'app:yt'),
              LayoutItem.pane(const Pane(id: 'pane')),
            ],
          ),
        ),
        Panel.empty('games', title: 'Games'),
      ],
    );
    expect(layout.itemIdFor('YouTube'), 'youtube-2');
    expect(layout.itemIdFor('Netflix'), 'netflix');
    expect(layout.paneIdFor(), 'pane-2');
    expect(layout.panelIdFor('Games'), 'games-2');
    // A folder cannot take the id of the home screen or of a sidebar,
    // there or not.
    expect(layout.panelIdFor('Home'), 'home-2');
    expect(layout.panelIdFor('Left'), 'left-2');
  });

  test('an app is named after its package, whatever it is called', () {
    expect(packageSlug('io.gh.reisxd.tizentube.cobalt'), 'tizentube-cobalt');
    expect(packageSlug('au.com.tenplay'), 'tenplay');
    expect(packageSlug('au.com.ninenow.ctv'), 'ninenow-ctv');
    expect(packageSlug('com.github.damontecres.wholphin'), 'wholphin');
    expect(packageSlug('com.netflix.ninja'), 'netflix-ninja');
    // Something is always left.
    expect(packageSlug('tv'), 'tv');
    expect(packageSlug('com.github'), 'github');
  });

  test('entities placed nowhere are named after what they are', () {
    final shown = Layout.initial().withEntities(
      ['app:io.gh.reisxd.tizentube.cobalt', 'input:x/HW15', 'input:x/HW16'],
      names: {
        'app:io.gh.reisxd.tizentube.cobalt': 'YouTube',
        'input:x/HW15': 'HDMI 1',
      },
    );
    expect(shown.home.items.map((i) => i.id), [
      'tizentube-cobalt',
      'hdmi-1',
      'hw16',
    ]);
  });
}
