import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// A small picture of another node and what is in it.
const previewModule = ModuleType(
  'preview',
  'Preview',
  visual: true,
  fields: [Field('node', 'Node ID', FieldKind.template)],
);
