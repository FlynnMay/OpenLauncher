import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';

void main() {
  final entity = builtInPrefabs.first;
  const plain = LayoutItem(
    id: 'a',
    kind: ItemKind.prefab,
    ref: cardPrefabId,
    vars: {'source': Variable('app:a')},
  );
  Map<String, Object?> part(PrefabInstance instance, String id) =>
      instance.parts.firstWhere((part) => part.id == id).options;

  test('a prefab is saved and read back as it was', () {
    final read = Prefab.fromJson(entity.toJson())!;
    expect(read.toJson(), entity.toJson());
    expect(read.layouts.keys, ['stacked', 'row']);
    expect(
      Prefab.listFromJson([entity.toJson(), entity.toJson(), 7]),
      hasLength(1),
    );
    expect(Prefab.fromJson({'id': 'Not An Id'}), isNull);
  });

  Object? size(PrefabInstance instance) =>
      (part(instance, 'name')[styleOption]! as Map)['fontSize'];

  test('an instance is its prefab until it says otherwise', () {
    final instance = instanceOf(entity, plain)!;
    expect(instance.layoutName, 'stacked');
    expect(part(instance, 'name')['text'], '{{source.label}}');
    expect(instance.parts.every((part) => !part.hidden), isTrue);
    expect(instance.triggers(plain), {
      Trigger.press: [const Act('open')],
      Trigger.hold: [const Act('menu')],
    });
  });

  test('what an instance sets is its own, value by value', () {
    final options = withOverrides(
      withOverrides(
        const {layoutOption: 'row'},
        'name',
        {
          styleOption: {'fontSize': 20},
        },
      ),
      'picture',
      {hiddenOption: true},
    );
    final item = plain.copyWith(options: options, on: {Trigger.hold: const []});
    final instance = instanceOf(entity, item)!;
    expect(instance.layoutName, 'row');
    // Its look is set over property by property: what the layout says of
    // the part still counts, and what the prefab does, under what it set.
    expect(part(instance, 'name')[styleOption], {
      'fontSize': 20,
      'fontWeight': 'medium',
      'textAlign': 'left',
    });
    expect(instance.parts.first.hidden, isTrue);
    expect(instance.triggers(item)[Trigger.hold], isEmpty);
    expect(instance.triggers(item)[Trigger.press], [const Act('open')]);

    // The prefab changes: the instance follows, but for what it set.
    final changed = entity.copyWith(
      parts: {
        ...entity.parts,
        'name': const PrefabPart('text', {
          'text': 'App: {{source.label}}',
          'style': {'fontSize': 30},
        }),
      },
    );
    final followed = instanceOf(changed, item)!;
    expect(part(followed, 'name')['text'], 'App: {{source.label}}');
    expect(size(followed), 20);
    expect(size(instanceOf(changed, plain)!), 30);

    // A value handed back is the prefab's again.
    final back = item.copyWith(
      options: withOverrides(options, 'name', {
        styleOption: {'fontSize': null},
      }),
    );
    expect(size(instanceOf(changed, back)!), 30);
    expect((back.options[partsOption]! as Map).keys, ['picture']);
  });

  test("a pane's rule counts over what an instance says", () {
    final item = plain.copyWith(
      options: withOverrides(
        const {layoutOption: 'row'},
        'name',
        {
          hiddenOption: true,
          styleOption: {'fontSize': 20},
        },
      ),
    );
    final ruled = item.copyWith(
      options: underRule(item.options, const {
        layoutOption: 'stacked',
        partsOption: {
          'name': {hiddenOption: false},
        },
      }),
    );
    final instance = instanceOf(entity, ruled)!;
    expect(instance.layoutName, 'stacked');
    expect(instance.parts.last.hidden, isFalse);
    // What the rule says nothing of is still the instance's.
    expect(size(instance), 20);
  });

  test('an entity that opens a folder is an instance too', () {
    final folder = LayoutItem.of('games', id: 'f', prefab: folderPrefabId);
    expect(prefabIdOf(folder), folderPrefabId);
    final prefab = builtInPrefabs.firstWhere(
      (prefab) => prefab.id == folderPrefabId,
    );
    final instance = instanceOf(prefab, folder)!;
    expect(instance.parts.first.kind, 'folder');
    // What it does is set the `open` of whatever it is drawn from: said in
    // the prefab, against its `source`, like anything else.
    expect(instance.triggers(folder)[Trigger.press], [
      const Act('set', {'var': 'open', 'value': true, 'of': '{{source.id}}'}),
    ]);
    expect(folder.source, 'games');
  });

  test("the user's prefabs are settings like any other", () {
    final own = entity.copyWith(id: 'big-entity', name: 'Big entity');
    final config = LauncherConfig().patched({
      'prefabs': [own.toJson(), 'nonsense'],
    });
    expect(config.prefabs.single.name, 'Big entity');
    expect(
      LauncherConfig.fromJson(config.toJson()).prefabs.single.toJson(),
      own.toJson(),
    );
  });
}
