import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/validation/layout_rules.dart';
import 'package:openlauncher_domain/validation/layout_validator.dart';
import 'package:test/test.dart';

Node card(String id) =>
    Node.of('app:$id', id: id, prefab: 'card', variable: 'what');

Node nested(String id, int levels) => levels == 0
    ? card('$id-leaf')
    : Node.layout(id: '$id$levels', children: [nested(id, levels - 1)]);

Layout layoutOf(Node root, {String? inbox, String startup = 'home'}) => Layout(
  inbox: inbox ?? root.id,
  screens: [Screen(id: 'home', root: root)],
  startup: Startup(startup),
);

Set<String> rulesBroken(Iterable<LayoutProblem> problems) => {
  for (final problem in problems) problem.ruleName,
};

void main() {
  const validator = LayoutValidator();

  group('a whole layout', () {
    test('a blank layout has no problems', () {
      expect(validator.validateLayout(Layout.blank()), isEmpty);
    });

    test('an id on two nodes is found', () {
      final layout = layoutOf(
        Node.layout(id: 'root', children: [card('a'), card('a')]),
      );
      final problems = validator.validateLayout(layout);
      expect(rulesBroken(problems), {const UniqueNodeIds().name});
      expect(problems.single.nodeId, 'a');
    });

    test('nesting past the limit is found at the node that is too deep', () {
      final layout = layoutOf(
        Node.layout(id: 'root', children: [nested('n', Node.maxDepth)]),
      );
      final problems = validator.validateLayout(layout);
      expect(rulesBroken(problems), {const NestingNotTooDeep().name});
      expect(problems.single.nodeId, 'n1');
    });

    test('a missing startup screen and a missing inbox are found', () {
      final layout = layoutOf(
        Node.layout(id: 'root', children: [card('a')]),
        inbox: 'nowhere',
        startup: 'elsewhere',
      );
      expect(rulesBroken(validator.validateLayout(layout)), {
        const StartupScreenExists().name,
        const InboxExists().name,
      });
    });

    test('a layout with no screen is found', () {
      final none = Layout(
        inbox: 'x',
        screens: const [],
        startup: const Startup(''),
      );
      expect(rulesBroken(validator.validateLayout(none)), {
        const HasAScreen().name,
      });
    });
  });

  group('part of a layout', () {
    final layout = layoutOf(
      Node.layout(
        id: 'root',
        children: [
          card('a'),
          card('a'),
          Node.layout(id: 'inner', children: [card('b'), card('b')]),
        ],
      ),
    );

    test('a node and what it holds are judged where they sit', () {
      final problems = validator.validateNodeAndBelow(layout, 'inner');
      expect({for (final p in problems) p.nodeId}, {'b'});
    });

    test('an id that is not there has nothing to judge', () {
      expect(validator.validateNodeAndBelow(layout, 'nope'), isEmpty);
    });
  });

  group('what a change adds', () {
    test('a fault that was already there is not blamed on the change', () {
      final before = layoutOf(
        Node.layout(id: 'root', children: [card('a'), card('a')]),
      );
      final after = layoutOf(
        Node.layout(id: 'root', children: [card('a'), card('a'), card('c')]),
      );
      expect(validator.problemsAdded(before: before, after: after), isEmpty);
    });

    test('a new fault is', () {
      final before = layoutOf(Node.layout(id: 'root', children: [card('a')]));
      final after = layoutOf(
        Node.layout(id: 'root', children: [card('a'), card('a')]),
      );
      expect(
        rulesBroken(validator.problemsAdded(before: before, after: after)),
        {const UniqueNodeIds().name},
      );
    });
  });

  test('a validator can be given only the rules wanted', () {
    final layout = layoutOf(
      Node.layout(id: 'root', children: [card('a'), card('a')]),
    );
    expect(
      const LayoutValidator([NestingNotTooDeep()]).validateLayout(layout),
      isEmpty,
    );
  });
}
