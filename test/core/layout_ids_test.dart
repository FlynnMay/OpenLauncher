import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';

import '../support/packs.dart';

Node _entity(String id, String ref) => cardOf(ref, id: id);

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
      layers: [
        Layer(
          id: 'home',
          root: Node.layout(
            id: 'home/root',
            children: [
              _entity('youtube', 'system:app/yt'),
              Node.layout(id: 'pane'),
              folderOf('games', title: 'Games'),
            ],
          ),
        ),
      ],
    );
    expect(layout.itemIdFor('YouTube'), 'youtube-2');
    expect(layout.itemIdFor('Netflix'), 'netflix');
    expect(layout.containerIdFor(), 'pane-2');
    // A folder is a pane: one id space for everything.
    expect(layout.containerIdFor('Games', 'folder'), 'games-2');
    expect(layout.containerIdFor('', 'folder'), 'folder');
    // Nothing can take the id of the home layer, there or not.
    expect(layout.containerIdFor('Home'), 'home-2');
    expect(layout.itemIdFor('Quick actions'), 'quick-actions');
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
    final shown = homeLayout().withEntities(
      [
        'system:app/io.gh.reisxd.tizentube.cobalt',
        'system:input/x/HW15',
        'system:input/x/HW16',
      ],
      names: {
        'system:app/io.gh.reisxd.tizentube.cobalt': 'YouTube',
        'system:input/x/HW15': 'HDMI 1',
      },
      instance: placedCard,
    );
    expect(shown.items.where((i) => i.handed.isNotEmpty).map((i) => i.id), [
      'tizentube-cobalt',
      'hdmi-1',
      'hw16',
    ]);
  });
}
