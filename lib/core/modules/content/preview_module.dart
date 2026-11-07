import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// A small picture of another node and what is in it.
const previewModule = ModuleType(
  'preview',
  'Preview',
  visual: true,
  fields: [Field('node', 'Node ID', FieldKind.template)],
);
