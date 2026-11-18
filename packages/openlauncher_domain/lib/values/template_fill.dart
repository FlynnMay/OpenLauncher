import 'package:openlauncher_domain/json/json_walk.dart';
import 'package:openlauncher_domain/values/template.dart';

/// [json] with every template text in it replaced by [valueOf] its text,
/// however deep. Text without a slot is left as it is.
Object? fillTemplates(
  Object? json,
  Object? Function(String template) valueOf,
) => walkJson(json, onText: (text) => isTemplate(text) ? valueOf(text) : text);

/// [json] with the slots that read only [roots] filled from [lookup]. Other
/// slots are left as written, and a lone slot keeps its value's type.
Object? fillSlots(
  Object? json,
  Set<String> roots,
  Object? Function(String root) lookup,
) => fillTemplates(
  json,
  (template) => Template.parse(template).fill(roots, lookup),
);
