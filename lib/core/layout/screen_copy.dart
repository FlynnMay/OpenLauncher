import 'package:openlauncher/core/layout/screen.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// A copy of a screen: new nodes, with ids under the new screen's.
typedef ScreenCopy = ({Screen screen, Map<String, String> renamed});

extension CopiedScreen on Screen {
  /// This screen as [newId]. Every node gets an id of the form `newId/name`,
  /// and what names one of them (an `of` argument, an entity variable) names
  /// the new node. Prefabs stay shared; what they name resolves by [find].
  ScreenCopy copied(String newId) {
    final renamed = <String, String>{};
    String named(String old) {
      final local = old.startsWith('$id/') ? old.substring(id.length + 1) : old;
      return renamed.putIfAbsent(old, () => '$newId/$local');
    }

    void collect(Object? json) {
      switch (json) {
        case final Map<Object?, Object?> map:
          if (map['id'] case final String old) named(old);
          map.values.forEach(collect);
        case final List<Object?> list:
          list.forEach(collect);
      }
    }

    Object? rewrite(Object? json) => switch (json) {
      final Map<Object?, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          key: switch (value) {
            final String text
                when key == 'id' ||
                    key == 'of' ||
                    (key == 'value' && map['type'] == 'entity') =>
              renamed[text] ?? text,
            _ => rewrite(value),
          },
      },
      final List<Object?> list => [for (final one in list) rewrite(one)],
      _ => json,
    };

    final json = root.toJson();
    renamed[root.id] = Screen.rootId(newId);
    collect(json);
    final copy = Node.fromJson(rewrite(json)! as Map<Object?, Object?>);
    return (screen: Screen(id: newId, root: copy), renamed: renamed);
  }
}
