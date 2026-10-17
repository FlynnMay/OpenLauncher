import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/editing/editing.dart';

import '../support/packs.dart';

void main() {
  final prefabs = {for (final prefab in systemPrefabs) prefab.id: prefab};

  group('a module switched off', () {
    const off = Node(
      id: 'a',
      modules: {
        'text': {'text': 'Hi', enabledKey: false},
        'focus': {'scale': 120, enabledKey: false},
        'style': {'background': '#ff0000ff', enabledKey: true},
      },
    );

    test('is kept but read as absent', () {
      expect(off.added('focus'), isTrue);
      expect(off.isOff('focus'), isTrue);
      expect(off.has('focus'), isFalse);
      expect(off.focusable, isFalse);
      expect(off.values('focus'), isNull);
      expect(off.visual, isNull);
      // Switched on, it reads without the switch.
      expect(off.style, {'background': '#ff0000ff'});
      expect(Node.fromJson(off.toJson()).modules, off.modules);
    });

    test('stays off when its values are replaced', () {
      final styled = off
          .withModule('focus', const {'scale': 104})
          .withVars({'label': const Variable('Hi')})
          .withModule('variables', null)
          .withVars({'label': const Variable('Hi')});
      expect(styled.isOff('focus'), isTrue);
      expect(styled.values('focus'), isNull);
      expect(styled.modules['focus'], {enabledKey: false, 'scale': 104});
      // Its switch is a value like any other.
      final on = styled.withValue('focus', enabledKey, null);
      expect(on.focusScale, 1.04);
      final pressed = withPressable(off, {
        Trigger.press: [
          const Act('open', {'entity': 'x'}),
        ],
      });
      expect(pressed.isOff('focus'), isTrue, reason: 'not switched on');
    });

    test('an instance switches off what its prefab has, or back on', () {
      final button = Node(
        id: 'b',
        prefab: 'system:button',
        modules: const {
          'focus': {enabledKey: false},
        },
      );
      final drawn = resolved(button, prefabs);
      expect(drawn.added('focus'), isTrue);
      expect(drawn.focusable, isFalse);
      // The prefab's values stay under the switch.
      expect(drawn.modules['focus']?['scale'], 103);

      final prefab = prefabs['system:button']!;
      final offInPrefab = {
        ...prefabs,
        prefab.id: prefab.copyWith(
          root: prefab.root.withValue('focus', enabledKey, false),
        ),
      };
      expect(
        resolved(button.withModule('focus', null), offInPrefab).focusable,
        isFalse,
      );
      expect(
        resolved(
          button.withModule('focus', const {enabledKey: true}),
          offInPrefab,
        ).focusable,
        isTrue,
      );
    });

    test('variables merge with the switch and no variable takes its name', () {
      final merged = variablesModule.merge(
        {'label': const Variable('Hi').toJson()},
        {enabledKey: false},
      );
      expect(switchedOff(merged), isTrue);
      expect(
        variablesFromForm([
          {'name': enabledKey, 'value': 'x'},
          {'name': 'label', 'value': 'y'},
        ]).keys,
        ['label'],
      );
    });
  });
}
