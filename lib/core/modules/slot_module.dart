import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Where an instance's own children go: after this node's children, in the
/// order the instance gives them, from its prefab's nodes variable [variable].
const slotModule = ModuleType(
  'slot',
  'Slot',
  fields: [Field('variable', 'Variable', FieldKind.text)],
);

/// The id of the node holding what instance [instance] puts in its slot
/// [variable].
String slotHolderId(String instance, String variable) => '$instance#$variable';

extension NodeSlot on Node {
  /// The nodes variable whose nodes it holds, if it is a slot or holds one.
  String? get slotVariable => switch (values(slotModule.name)?['variable']) {
    final String name when name.isNotEmpty => name,
    _ => null,
  };

  /// In a resolved instance: the id of the node in the layout that holds
  /// this slot's nodes, which the editor drops into.
  String? get slotHolder => switch (values(slotModule.name)?['holder']) {
    final String id => id,
    _ => null,
  };

  /// A node made to hold an instance's nodes for one slot.
  bool get holdsSlot => id.contains('#') && slotVariable != null;
}
