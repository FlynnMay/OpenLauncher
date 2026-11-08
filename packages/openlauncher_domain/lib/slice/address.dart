import 'package:openlauncher_domain/commands/command.dart';

/// Where in the config a [Slice] is loaded: the whole config, a prefab or
/// one of its children, or a node of the layout or one of its children as an
/// instance shows them.
sealed class Address {
  const Address();

  /// `/`, `prefab:<id>[@<variant>][/<child>]` or `layout:<node>[/<child>]`.
  /// Throws [CommandRefused] for anything else.
  factory Address.parse(String text) {
    final trimmed = text.trim();
    if (trimmed == '/') return const ConfigAddress();
    final prefab = _prefab.firstMatch(trimmed);
    if (prefab != null) {
      final child = prefab.group(3);
      return PrefabAddress(
        prefab.group(1)!,
        variant: prefab.group(2),
        child: child == null || child.isEmpty ? null : child,
      );
    }
    if (trimmed.startsWith('screen:') && trimmed.length > 'screen:'.length) {
      return ScreenAddress(trimmed.substring('screen:'.length));
    }
    if (trimmed.startsWith('layout:') && trimmed.length > 'layout:'.length) {
      return LayoutAddress(trimmed.substring('layout:'.length));
    }
    throw CommandRefused('"$text" is not an address.');
  }

  static final _prefab = RegExp(r'^prefab:([^@/]+)(?:@([^/]+))?(?:/(.*))?$');
}

/// The entire config.
class ConfigAddress extends Address {
  const ConfigAddress();

  @override
  String toString() => '/';

  @override
  bool operator ==(Object other) => other is ConfigAddress;

  @override
  int get hashCode => 0;
}

/// A prefab: its root, or [child] of it. With a [variant], what that variant
/// overrides.
class PrefabAddress extends Address {
  const PrefabAddress(this.prefabId, {this.variant, this.child});

  final String prefabId;
  final String? variant;
  final String? child;

  @override
  String toString() =>
      'prefab:$prefabId${variant == null ? '' : '@$variant'}'
      '${child == null ? '/' : '/$child'}';

  @override
  bool operator ==(Object other) =>
      other is PrefabAddress &&
      other.prefabId == prefabId &&
      other.variant == variant &&
      other.child == child;

  @override
  int get hashCode => Object.hash(prefabId, variant, child);
}

/// A node of the layout, or a child of the prefab an instance shows. Node ids
/// can hold `/` themselves, so what is the node and what is the child is
/// decided against the layout, by [LayoutAddress.split].
class LayoutAddress extends Address {
  const LayoutAddress(this.path);

  /// A node and a child of its prefab.
  LayoutAddress.child(String nodeId, String child) : path = '$nodeId/$child';

  /// The node id, or the node id and the child's id after a `/`.
  final String path;

  @override
  String toString() => 'layout:$path';

  @override
  bool operator ==(Object other) =>
      other is LayoutAddress && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A screen as a whole: its label, its place among the screens.
class ScreenAddress extends Address {
  const ScreenAddress(this.screenId);

  final String screenId;

  @override
  String toString() => 'screen:$screenId';

  @override
  bool operator ==(Object other) =>
      other is ScreenAddress && other.screenId == screenId;

  @override
  int get hashCode => screenId.hashCode;
}
