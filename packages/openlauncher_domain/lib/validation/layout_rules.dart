import 'package:openlauncher_domain/layout/tree.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/validation/layout_validator.dart';

/// The rules every layout must follow, in the order they are checked.
const List<LayoutRule> standardLayoutRules = [
  HasAScreen(),
  UniqueNodeIds(),
  NestingNotTooDeep(),
  StartupScreenExists(),
  InboxExists(),
];

class HasAScreen extends LayoutRule {
  const HasAScreen();

  @override
  String get name => 'has a screen';

  @override
  Iterable<LayoutProblem> checkLayout(LayoutContext context) =>
      context.layout.screens.isEmpty
      ? [LayoutProblem(name, 'A layout needs a screen.')]
      : const [];
}

class UniqueNodeIds extends LayoutRule {
  const UniqueNodeIds();

  @override
  String get name => 'unique node ids';

  @override
  Iterable<LayoutProblem> checkNode(NodeVisit visit) =>
      (visit.context.nodeCountsById[visit.node.id] ?? 1) > 1
      ? [
          LayoutProblem(
            name,
            '"${visit.node.id}" would be on two nodes.',
            nodeId: visit.node.id,
          ),
        ]
      : const [];
}

class NestingNotTooDeep extends LayoutRule {
  const NestingNotTooDeep();

  @override
  String get name => 'nesting not too deep';

  @override
  Iterable<LayoutProblem> checkNode(NodeVisit visit) =>
      visit.node.isContainer && visit.depth > Node.maxDepth
      ? [
          LayoutProblem(
            name,
            'Layouts can be nested ${Node.maxDepth - 1} deep.',
            nodeId: visit.node.id,
          ),
        ]
      : const [];
}

class StartupScreenExists extends LayoutRule {
  const StartupScreenExists();

  @override
  String get name => 'startup screen exists';

  @override
  Iterable<LayoutProblem> checkLayout(LayoutContext context) {
    final layout = context.layout;
    return layout.screens.isEmpty ||
            layout.screen(layout.startup.screen) != null
        ? const []
        : [
            LayoutProblem(
              name,
              'The startup screen "${layout.startup.screen}" is not there.',
            ),
          ];
  }
}

class InboxExists extends LayoutRule {
  const InboxExists();

  @override
  String get name => 'inbox exists';

  @override
  Iterable<LayoutProblem> checkLayout(LayoutContext context) {
    final layout = context.layout;
    final held = layout.screens.any(
      (screen) => screen.root.cellContainers.any(
        (container) => container.id == layout.inbox,
      ),
    );
    return held || layout.screens.isEmpty
        ? const []
        : [
            LayoutProblem(
              name,
              'The inbox "${layout.inbox}" is not a container in the layout.',
            ),
          ];
  }
}
