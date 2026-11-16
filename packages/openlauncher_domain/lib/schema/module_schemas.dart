import 'package:openlauncher_domain/actions/act.dart';
import 'package:openlauncher_domain/modules/logic/prefab_rules_module.dart';
import 'package:openlauncher_domain/modules/logic/triggers_module.dart';
import 'package:openlauncher_domain/modules/logic/variables_module.dart';
import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/modules/module_registry.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/schema/schema_parts.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// The name a module's schema goes by in the shared file.
String moduleSchemaName(ModuleType type) => 'module_${type.name}';

/// Each module's saved values as a schema, by [moduleSchemaName]. A module's
/// fields describe what it saves; the three that save something else say so.
Map<String, Schema> moduleSchemas() => {
  for (final type in moduleTypes) moduleSchemaName(type): _moduleSchema(type),
};

/// The properties for [fields], by key. A key that more than one field has
/// (shown under different conditions) accepts any of them.
Map<String, Schema> propertiesOf(List<Field> fields) {
  final byKey = <String, List<Schema>>{};
  for (final field in fields) {
    byKey.putIfAbsent(field.key, () => []).add(fieldSchema(field));
  }
  return {
    for (final MapEntry(:key, value: schemas) in byKey.entries)
      key: schemas.length == 1 ? schemas.single : {'anyOf': schemas},
  };
}

/// What a value of [field] looks like in JSON.
Schema fieldSchema(Field field) {
  final schema = _valueOf(field);
  final help = field.help.isEmpty ? '' : ' ${field.help}';
  return {
    ...schema,
    'description': '${field.label}.$help',
    if (_isJson(field.defaultValue)) 'default': field.defaultValue,
  };
}

// ---------------------------------------------------------------------------
// Private: one module
// ---------------------------------------------------------------------------

Schema _moduleSchema(ModuleType type) {
  final shaped = _shapedModules[type.name];
  if (shaped != null) return shaped();
  final properties = {
    enabledKey: _switch,
    ...propertiesOf([...type.fields, ...type.ownControls]),
  };
  return objectOf(
    properties,
    additional: [...type.fields, ...type.ownControls].isEmpty,
    description: type.label,
  );
}

final _switch = toggle(description: 'Switches the module off when false.');

// ---------------------------------------------------------------------------
// Private: modules that save something other than their fields
// ---------------------------------------------------------------------------

final _shapedModules = <String, Schema Function()>{
  triggersModule.name: _triggers,
  variablesModule.name: _variables,
  prefabRulesModule.name: _prefabRules,
};

Schema _triggers() => objectOf({
  enabledKey: _switch,
  for (final trigger in Trigger.values)
    trigger.name: listOf(common('act'), description: trigger.label),
}, description: 'What it does when pressed, held, focused, shown or hidden.');

Schema _variables() => _namedBy(common('variable'), 'Named values, by name.');

Schema _prefabRules() => _namedBy(
  objectOf({'variant': text(), 'overrides': common('overrides')}),
  'Per prefab, what every instance directly inside gets.',
);

/// An object of [values] by name, that can also be switched off.
Schema _namedBy(Schema values, String description) => {
  ...mapOf(values, description: description),
  'properties': {enabledKey: _switch},
};

// ---------------------------------------------------------------------------
// Private: the value of one field
// ---------------------------------------------------------------------------

Schema _valueOf(Field field) => switch (field.kind) {
  FieldKind.template || FieldKind.text || FieldKind.icon => orUse(text()),
  FieldKind.number => orTemplate(number()),
  FieldKind.toggle => orTemplate(toggle()),
  FieldKind.choice => _choice(field),
  FieldKind.colour => orTemplate(_colour),
  FieldKind.fill => orTemplate({
    'anyOf': [_colour, _gradient],
  }),
  FieldKind.corners => orTemplate({
    'anyOf': [
      number(),
      {'type': 'array', 'items': number(), 'minItems': 4, 'maxItems': 4},
    ],
  }),
  FieldKind.value => <String, Object?>{},
  FieldKind.list => orUse(
    listOf(
      objectOf(
        propertiesOf(field.fields?.call({...field.blank}) ?? const []),
        additional: true,
      ),
    ),
  ),
  FieldKind.group => objectOf(propertiesOf(field.group)),
};

Schema _choice(Field field) {
  if (field.choices.isEmpty) return orUse(text());
  final one = oneOfText(field.choices.keys);
  return field.multiple ? orUse(listOf(one)) : orTemplate(one);
}

final _colour = text(
  pattern: r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);

final _gradient = objectOf({
  'colors': {'type': 'array', 'items': _colour},
  'stops': {'type': 'array', 'items': number()},
  'angle': number(),
});

bool _isJson(Object? value) => value is String || value is num || value is bool;
