import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher_domain/layout/layout.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// What `{{root...}}` reads for the address [root], as the node [reader].
/// A plain id reads as it always did; children, modules and the words `self`,
/// `parent` and `root` are followed through the tree, each hop by the access
/// of what it reaches.
final nodeValueProvider = Provider.autoDispose
    .family<Object?, ({String root, String? reader})>((ref, ask) {
      final path = NodePath.parse(ask.root);
      if (path.isWholeId) {
        return ref.watch(entityDataProvider(ask.root)) ??
            ref.watch(componentDataProvider(ask.root));
      }
      final layout = ref.watch(
        configProvider.select((config) => config.value?.layout),
      );
      if (layout == null) return null;
      final reading = _NodeReading(
        ref.watch,
        layout,
        ref.watch(prefabsProvider),
        ask.reader,
      );
      return reading.read(path);
    });

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

class _NodeReading {
  _NodeReading(this._watch, this._layout, this._prefabs, this._reader);

  final Watch _watch;
  final Layout _layout;
  final Map<String, Prefab> _prefabs;
  final String? _reader;

  Object? read(NodePath path) {
    final (start, children) = _start(path);
    if (start == null) return _entityOrNothing(path);
    final node = _followed(start, children);
    if (node == null) return null;
    final module = path.module;
    return module == null ? _variablesOf(node) : _moduleOf(node, module);
  }

  (Node?, List<String>) _start(NodePath path) {
    final keyword = path.keyword;
    if (keyword != null) {
      final id = _keywordId(keyword);
      return (
        id == null ? null : _nodeById(id),
        path.segments.skip(1).toList(),
      );
    }
    for (var count = path.segments.length; count > 0; count--) {
      final found = _nodeById(path.idOf(count));
      if (found != null) return (found, path.segments.skip(count).toList());
    }
    return (null, const []);
  }

  Object? _entityOrNothing(NodePath path) => path.module == null
      ? _watch(entityDataProvider(path.idOf(path.segments.length)))
      : null;

  Node? _followed(Node start, List<String> children) {
    var node = start;
    for (final segment in children) {
      final child = _childOf(node, segment);
      if (child == null || !_mayReachChild(node, child)) return null;
      node = child;
    }
    return node;
  }

  Object? _variablesOf(Node node) {
    final scope = scopeOf(
      _watch,
      node.id,
      variablesOf(node, _prefabs),
      const {},
    );
    final shown = switch (_relation(node.id)) {
      _Relation.itself => scope.own,
      _Relation.under => scope.inner,
      _Relation.outside => scope.public,
    };
    return {...shown}..remove(readerKey);
  }

  Object? _moduleOf(Node node, String module) {
    final allowed = switch (node.accessOfModule(module)) {
      NodeAccess.private => _relation(node.id) == _Relation.itself,
      NodeAccess.protected => _relation(node.id) != _Relation.outside,
      NodeAccess.public => true,
    };
    return allowed ? resolved(node, _prefabs).values(module) : null;
  }

  bool _mayReachChild(Node parent, Node child) => switch (child.access) {
    NodeAccess.private => _reader == child.id,
    NodeAccess.protected => _relation(parent.id) != _Relation.outside,
    NodeAccess.public => true,
  };

  _Relation _relation(String id) {
    final reader = _reader;
    if (reader == null) return _Relation.outside;
    if (reader == id) return _Relation.itself;
    if (reader.startsWith('$id/')) return _Relation.under;
    final held = _nodeById(id);
    final under =
        held != null &&
        resolved(held, _prefabs).all.any((node) => node.id == reader);
    return under ? _Relation.under : _Relation.outside;
  }

  Node? _nodeById(String id) {
    final saved = _layout.find(id);
    if (saved != null) return saved;
    for (
      var at = id.lastIndexOf('/');
      at > 0;
      at = id.lastIndexOf('/', at - 1)
    ) {
      final instance = _layout.find(id.substring(0, at));
      if (instance == null || !instance.isInstance) continue;
      return resolved(
        instance,
        _prefabs,
      ).all.where((node) => node.id == id).firstOrNull;
    }
    return null;
  }

  Node? _childOf(Node node, String segment) {
    final inside = resolved(node, _prefabs);
    bool named(Node child) =>
        child.id == segment || child.id.endsWith('/$segment');
    return inside.children.where(named).firstOrNull ??
        inside.all
            .where((child) => child != inside && named(child))
            .firstOrNull;
  }

  String? _keywordId(String keyword) => switch (_reader) {
    null => null,
    final reader => switch (keyword) {
      'self' => reader,
      'parent' => _parentOf(reader),
      _ => _rootOf(reader),
    },
  };

  String? _parentOf(String id) {
    final saved = _layout.all
        .where((node) => node.children.any((child) => child.id == id))
        .firstOrNull;
    if (saved != null) return saved.id;
    final instance = _instanceHolding(id);
    return instance == null
        ? null
        : resolved(instance, _prefabs).all
              .where((node) => node.children.any((child) => child.id == id))
              .firstOrNull
              ?.id;
  }

  String? _rootOf(String id) {
    if (_layout.find(id) == null) return _instanceHolding(id)?.id;
    return _layout.screens
        .where((screen) => screen.root.all.any((node) => node.id == id))
        .firstOrNull
        ?.root
        .id;
  }

  Node? _instanceHolding(String id) {
    for (
      var at = id.lastIndexOf('/');
      at > 0;
      at = id.lastIndexOf('/', at - 1)
    ) {
      final instance = _layout.find(id.substring(0, at));
      if (instance != null && instance.isInstance) return instance;
    }
    return null;
  }
}

enum _Relation { itself, under, outside }
