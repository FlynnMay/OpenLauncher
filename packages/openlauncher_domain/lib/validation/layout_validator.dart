import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/validation/layout_rules.dart';

/// One thing wrong with a layout. Two problems are the same if the same rule
/// finds the same fault on the same node.
class LayoutProblem {
  const LayoutProblem(this.ruleName, this.message, {this.nodeId});

  final String ruleName;
  final String message;

  /// The node it is about; none for a fault of the whole layout.
  final String? nodeId;

  @override
  bool operator ==(Object other) =>
      other is LayoutProblem &&
      other.ruleName == ruleName &&
      other.nodeId == nodeId &&
      other.message == message;

  @override
  int get hashCode => Object.hash(ruleName, nodeId, message);

  @override
  String toString() => message;
}

/// What a rule can ask about the layout being checked.
class LayoutContext {
  LayoutContext(this.layout);

  final Layout layout;

  /// How many nodes carry each id.
  late final Map<String, int> nodeCountsById = () {
    final counts = <String, int>{};
    for (final node in layout.all) {
      counts[node.id] = (counts[node.id] ?? 0) + 1;
    }
    return counts;
  }();
}

/// A node as the walk meets it, with where it is.
class NodeVisit {
  const NodeVisit({
    required this.context,
    required this.screen,
    required this.node,
    required this.parent,
    required this.depth,
  });

  final LayoutContext context;
  final Screen screen;
  final Node node;
  final Node? parent;

  /// How deep layouts are nested here: a screen's root is 1, a container
  /// that is docked starts again at 1, and what an instance holds is as deep
  /// as the instance.
  final int depth;
}

/// One thing that must hold of a layout. A rule looks at the whole layout, at
/// each node, or both; what it does not look at it leaves alone.
abstract class LayoutRule {
  const LayoutRule();

  /// Names the rule in a [LayoutProblem].
  String get name;

  Iterable<LayoutProblem> checkLayout(LayoutContext context) => const [];

  Iterable<LayoutProblem> checkNode(NodeVisit visit) => const [];
}

/// Checks a layout against its rules: all of it, one node and what it holds,
/// or what a change brought that was not there before.
class LayoutValidator {
  const LayoutValidator([this.rules = standardLayoutRules]);

  final List<LayoutRule> rules;

  /// Every problem in [layout].
  Set<LayoutProblem> validateLayout(Layout layout) {
    final context = LayoutContext(layout);
    return {
      for (final rule in rules) ...rule.checkLayout(context),
      for (final visit in _visits(context)) ..._nodeProblems(visit),
    };
  }

  /// The problems of the node [nodeId] and everything it holds, judged by
  /// where it sits in [layout]. Faults of the layout as a whole are left out.
  Set<LayoutProblem> validateNodeAndBelow(Layout layout, String nodeId) {
    final context = LayoutContext(layout);
    final below = layout.node(nodeId)?.all.toSet() ?? const <Node>{};
    return {
      for (final visit in _visits(context))
        if (below.contains(visit.node)) ..._nodeProblems(visit),
    };
  }

  /// The problems [after] has that [before] did not. A layout that was
  /// already wrong can still be edited, as long as the edit adds no fault.
  List<LayoutProblem> problemsAdded({
    required Layout before,
    required Layout after,
  }) => validateLayout(after).difference(validateLayout(before)).toList();

  Iterable<LayoutProblem> _nodeProblems(NodeVisit visit) => [
    for (final rule in rules) ...rule.checkNode(visit),
  ];

  Iterable<NodeVisit> _visits(LayoutContext context) sync* {
    for (final screen in context.layout.screens) {
      yield* _walk(context, screen, screen.root, null, 1);
    }
  }

  Iterable<NodeVisit> _walk(
    LayoutContext context,
    Screen screen,
    Node node,
    Node? parent,
    int depth,
  ) sync* {
    final here = node.offCells ? 1 : depth;
    yield NodeVisit(
      context: context,
      screen: screen,
      node: node,
      parent: parent,
      depth: here,
    );
    final belowDepth = node.isInstance ? here : here + 1;
    for (final child in node.children) {
      yield* _walk(context, screen, child, node, belowDepth);
    }
  }
}
