import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// Something lifted out of the config as plain data, to be put somewhere
/// else. It holds no place in the config.
sealed class Clip {
  const Clip();

  factory Clip.fromJson(Json json) => switch (json['kind']) {
    NodeClip.kind => NodeClip(
      Node.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'node')),
      cut: jsonOptional<bool>(json, 'cut') ?? false,
    ),
    ModuleClip.kind => ModuleClip(
      jsonRequired<String>(json, 'module'),
      jsonObject(json['values']),
    ),
    _ => throw const CommandRefused('That is not something to paste.'),
  };

  Map<String, Object?> toJson();
}

/// A node and everything in it. A cut one keeps its ids where they are free;
/// a copy gets new ones where they are taken.
class NodeClip extends Clip {
  const NodeClip(this.node, {this.cut = false});

  static const kind = 'node';

  final Node node;
  final bool cut;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'node': node.toJson(),
    if (cut) 'cut': true,
  };
}

/// The values of one module.
class ModuleClip extends Clip {
  const ModuleClip(this.module, this.values);

  static const kind = 'module';

  final String module;
  final ModuleValues values;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'module': module,
    'values': values,
  };
}
