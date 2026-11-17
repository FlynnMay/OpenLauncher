import 'package:openlauncher_domain/fields/field_spec.dart';
import 'package:openlauncher_domain/modules/module_registry.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/packs/pack_kind.dart';
import 'package:openlauncher_domain/schema/module_schemas.dart';
import 'package:openlauncher_domain/schema/schema_parts.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/variables/variable.dart';

export 'package:openlauncher_domain/schema/schema_parts.dart'
    show schemaBaseUrl, schemaText;

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

/// The file a [kind] of pack file is checked by.
String schemaFileOf(PackKind kind) => '${kind.name}.schema.json';

const packManifestSchemaFile = 'pack.schema.json';
const defsSchemaFile = 'defs.schema.json';

/// The URL a pack file names in its `$schema` to be checked as a [kind].
String schemaUrlOf(PackKind kind) => '$schemaBaseUrl${schemaFileOf(kind)}';

/// Every schema, by the file it is written to. They are made from the same
/// descriptions the launcher reads packs by, so a new module or style
/// property is in them without being written twice.
Map<String, Schema> packSchemas() => {
  commonFile: _commonSchema(),
  packManifestSchemaFile: _document(
    packManifestSchemaFile,
    'Pack manifest',
    _manifest(),
  ),
  defsSchemaFile: _document(defsSchemaFile, 'Reusable chunks', _defsFile()),
  for (final kind in PackKind.values)
    schemaFileOf(kind): _kindDocument(kind, _oneOf(kind)),
};

// ---------------------------------------------------------------------------
// Private: whole files
// ---------------------------------------------------------------------------

const _draft = 'https://json-schema.org/draft/2020-12/schema';

Schema _document(String file, String title, Schema body) => {
  r'$schema': _draft,
  r'$id': '$schemaBaseUrl$file',
  'title': title,
  ...body,
};

Schema _commonSchema() => _document(commonFile, 'Shared pieces', {
  r'$defs': {
    'template': {
      'type': 'string',
      'pattern': r'\{\{',
      'description': 'Text with {{values}} filled in where it is read.',
    },
    'use': {
      'type': 'object',
      'properties': {
        r'$use': text(description: 'The name of the chunk to put here.'),
        'params': {'type': 'object'},
      },
      'required': [r'$use'],
      'description': 'A chunk from \$defs, with the keys beside it on top.',
    },
    'spread': {
      'type': 'object',
      'properties': {
        r'$spread': text(description: 'The name of a list chunk.'),
      },
      'required': [r'$spread'],
      'additionalProperties': false,
      'description': 'The items of a list chunk, put here.',
    },
    'transform': _transform(),
    'act': _act(),
    'variable': _variable(),
    'overrides': _overrides(),
    'nodeOverride': _nodeOverride(),
    'modules': _modules(),
    'node': _node(),
    'entityAction': _entityAction(),
    'source': _source(),
    'entity': _entity(),
    'fieldSpec': _fieldSpec(),
    ...moduleSchemas(),
  },
});

Schema _defsFile() => {
  'type': 'object',
  'properties': {
    r'$schema': text(),
    r'$comment': text(),
    r'$defs': {'type': 'object'},
  },
  'additionalProperties': false,
};

/// A file of [kind]: one object of it, or several by name.
Schema _kindDocument(PackKind kind, Schema one) =>
    _document(schemaFileOf(kind), 'Pack ${kind.name} file', {
      r'$defs': {'one': one},
      'type': 'object',
      'if': {
        'anyOf': [
          for (final key in {...kind.ownKeys, r'$use'})
            {
              'required': [key],
            },
        ],
      },
      'then': {r'$ref': r'#/$defs/one'},
      'else': {
        'properties': {
          r'$schema': text(),
          r'$comment': text(),
          r'$defs': {'type': 'object'},
        },
        'additionalProperties': {r'$ref': r'#/$defs/one'},
      },
    });

// ---------------------------------------------------------------------------
// Private: what each kind of pack file holds
// ---------------------------------------------------------------------------

/// The schema of the one thing a file of [kind] holds.
Schema _oneOf(PackKind kind) => switch (kind) {
  PackKind.entity => common('entity'),
  PackKind.source => common('source'),
  PackKind.field => _premadeField(),
  PackKind.generator => _generator(),
  PackKind.prefab => _prefab(),
  PackKind.screen => _screen(),
};

Schema _premadeField() => objectOf({
  'extends': text(description: 'The primitive or premade field it builds on.'),
  ..._fieldProperties(),
}, description: 'A field other fields can be made from.');

Schema _generator() => objectOf(
  {
    'from': text(description: 'The name of the source it reads.'),
    'where': text(description: 'A row makes an entity only when this is true.'),
    'entity': common('entity'),
    'tables': {'type': 'object', 'description': 'Lookup data, read as tables.'},
  },
  required: ['from', 'entity'],
  description: 'An entity for each row a source answers.',
);

Schema _prefab() => objectOf(
  {
    'id': text(description: 'A name without ":"; the pack adds its own.'),
    'name': text(),
    'card': text(description: 'The prefab an instance of this opens.'),
    'root': common('node'),
    'variants': mapOf(
      objectOf({'label': text(), 'overrides': common('overrides')}),
    ),
  },
  required: ['id', 'root'],
  description: 'A saved node, reused through instances.',
);

Schema _screen() => objectOf(
  {
    'id': text(),
    'start': toggle(description: 'The screen the launcher starts on.'),
    'inbox': text(description: 'Where new things are put.'),
    'root': common('node'),
  },
  required: ['id'],
  description: 'A screen of the launcher.',
);

Schema _manifest() => objectOf(
  {
    'id': text(pattern: r'^[a-z0-9][a-z0-9_-]{0,39}$'),
    'name': text(),
    'version': {
      'type': ['string', 'number'],
    },
    'author': text(),
    'licence': text(),
    'source': text(description: 'Where it is made, such as its repository.'),
    'app': text(description: 'The release of the launcher it was written for.'),
    'requires': {
      'type': 'array',
      'items': text(pattern: r'^[a-z0-9][a-z0-9_-]{0,39}$'),
    },
    'categories': mapOf(
      text(),
      description: 'What entity categories are called.',
    ),
    'settings': mapOf(
      common('fieldSpec'),
      description: 'What it asks the user.',
    ),
    'auth': mapOf(
      objectOf(
        {'host': text(), 'headers': mapOf(text())},
        required: ['host', 'headers'],
      ),
      description: 'How it signs requests, by profile name.',
    ),
  },
  required: ['id'],
  description: 'What a pack is, in its pack.json.',
);

// ---------------------------------------------------------------------------
// Private: nodes and their modules
// ---------------------------------------------------------------------------

Schema _transform() => objectOf({
  'anchors': _four('Left, top, right and bottom anchors, 0 to 1.'),
  'offsets': _four('Left, top, right and bottom offsets, in pixels.'),
}, description: 'Where it sits in a parent without a layout.');

Schema _four(String description) => {
  'type': 'array',
  'items': number(),
  'minItems': 4,
  'maxItems': 4,
  'description': description,
};

Schema _overrides() => mapOf(
  common('nodeOverride'),
  description: 'Changes to nodes of a prefab, by node id.',
);

Schema _nodeOverride() => objectOf({
  'name': text(),
  'transform': common('transform'),
  'modules': common('modules'),
});

Schema _modules() => objectOf({
  for (final type in moduleTypes)
    type.name: {...common(moduleSchemaName(type))},
}, description: 'What the node takes on; each module is one of these.');

Schema _node() => objectOf(
  {
    'id': text(description: 'Unique in its screen or prefab.'),
    'name': text(description: 'What the editor calls it.'),
    'prefab': text(description: 'The prefab this is an instance of.'),
    'variant': text(),
    'transform': common('transform'),
    'modules': common('modules'),
    'children': {'type': 'array', 'items': common('node')},
    'overrides': common('overrides'),
  },
  required: ['id'],
  description: 'One thing on screen, with the modules that make it so.',
);

// ---------------------------------------------------------------------------
// Private: acts and variables
// ---------------------------------------------------------------------------

Schema _act() => {
  'anyOf': [
    objectOf(
      {
        'run': text(description: 'An address such as launcher://screen/open.'),
        'with': {'type': 'object'},
      },
      required: ['run'],
      description: 'Calls an address.',
    ),
    objectOf(
      {'do': text(description: "The name of an entity's action.")},
      required: ['do'],
      additional: true,
      description: 'Runs an action of an entity; the other keys are its input.',
    ),
  ],
};

Schema _variable() => {
  'description':
      'A value, or an object with a value or a condition and a type.',
  'properties': {
    'value': <String, Object?>{},
    'type': {
      'description':
          'A type, or the premade field a value is: "location" or '
          '"system:location".',
      'type': 'string',
    },
    'with': {
      'type': 'object',
      'description':
          'For an entity: what it is asked with, as templates. Blank ones '
          'are not given.',
    },
    'access': oneOfText(VarAccess.values.map((access) => access.name)),
    'exposed': toggle(),
    'when': text(description: 'The template a conditional reads.'),
    'cases': {
      'type': 'array',
      'items': objectOf({
        for (final test in VarTest.values) test.name: <String, Object?>{},
        'then': <String, Object?>{},
      }, description: 'One case: a comparison, and what the value is then.'),
    },
    'else': <String, Object?>{},
  },
};

// ---------------------------------------------------------------------------
// Private: entities and sources
// ---------------------------------------------------------------------------

Schema _entityAction() => objectOf(
  {
    'run': text(description: 'The operation to run.'),
    'with': {'type': 'object'},
    'args': mapOf({
      'type': 'array',
      'items': {'type': 'string'},
    }),
    'label': text(),
    'icon': text(),
    'then': {
      'anyOf': [
        common('entityAction'),
        {'type': 'array', 'items': common('entityAction')},
      ],
    },
  },
  required: ['run'],
  description: 'What an entity can be told to do.',
);

Map<String, Schema> _sourceProperties() => {
  'url': text(description: 'http(s)://, os:// or launcher:// address.'),
  'every': number(description: 'Seconds between reads.'),
  'watch': toggle(description: 'Read again when the source says it changed.'),
  'rows': text(description: 'Path to the list in the answer.'),
  'method': oneOfText(Source.methods),
  'auth': text(description: "The pack's auth profile that signs the request."),
  'body': {
    'anyOf': [
      {'type': 'string'},
      {'type': 'object'},
    ],
  },
  'params': mapOf(
    objectOf({
      'type': text(description: 'The premade field that asks for it.'),
      'default': text(description: 'A template over settings.'),
      'required': toggle(description: 'Not asked while it has no value.'),
    }),
    description: 'What a caller may give; read as {{ask.name}}.',
  ),
};

Schema _source() => objectOf(
  _sourceProperties(),
  required: ['url'],
  description: 'Where values come from.',
);

Schema _entity() => objectOf(
  {
    'id': text(description: 'A name without ":"; the pack adds its own.'),
    'category': text(),
    'label': text(),
    'name': text(),
    'data': {'type': 'object', 'description': 'Values read as {{id.key}}.'},
    'feed': {
      'anyOf': [text(), common('source')],
    },
    'actions': mapOf(common('entityAction')),
    'prefab': text(),
    'placed': toggle(),
  },
  required: ['id'],
  description: 'Something with actions and readable values.',
);

// ---------------------------------------------------------------------------
// Private: fields
// ---------------------------------------------------------------------------

Schema _fieldSpec() => objectOf(
  _fieldProperties(),
  description: 'One field: a type and what that type takes.',
);

Map<String, Schema> _fieldProperties() => {
  'type': {
    'anyOf': [
      oneOfText(FieldType.values.map((type) => type.name)),
      text(description: 'The name of a premade field.'),
    ],
  },
  'label': text(),
  'help': text(),
  'required': toggle(),
  'secret': toggle(),
  'default': <String, Object?>{},
  'visible': text(description: 'A template; the field shows when it is true.'),
  'span': number(),
  'placeholder': text(),
  'multiline': toggle(),
  'pattern': text(),
  'minLength': number(),
  'maxLength': number(),
  'format': oneOfText(TextFormat.values.map((format) => format.name)),
  'min': number(),
  'max': number(),
  'step': number(),
  'decimal': toggle(),
  'options': {
    'anyOf': [
      mapOf(text()),
      {'type': 'array', 'items': {}},
    ],
  },
  'from': _optionsFrom(),
  'as': oneOfText(ChoiceLook.values.map((look) => look.name)),
  'unset': text(),
  'multiple': toggle(),
  'minChoices': number(),
  'maxChoices': number(),
  'fields': mapOf(common('fieldSpec')),
  'columns': number(),
};

Schema _optionsFrom() => objectOf(
  {
    ..._sourceProperties(),
    'label': text(description: 'How a row is listed.'),
    'value': text(),
    'group': text(),
    'where': text(),
    'keep': mapOf(text()),
    'on': oneOfText(FindOn.values.map((on) => on.name)),
    'debounce': number(),
    'minChars': number(),
  },
  required: ['url', 'label'],
  description: 'Options asked of the web.',
);
