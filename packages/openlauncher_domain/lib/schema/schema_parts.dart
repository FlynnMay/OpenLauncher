/// The small pieces JSON Schemas are built from. Deliberately not in any
/// barrel.
library;

import 'dart:convert';

typedef Schema = Map<String, Object?>;

/// Where the published schemas live; each file's `$id` and the `$schema` line
/// of a pack file are made from it.
const schemaBaseUrl =
    'https://raw.githubusercontent.com/FlynnMay/OpenLauncher/main/schemas/';

/// The file every schema takes its shared pieces from.
const commonFile = 'common.schema.json';

/// A reference to a shared piece in [commonFile].
Schema common(String name) => {r'$ref': '$commonFile#/\$defs/$name'};

/// Keys any object in a pack file may carry, whatever it is.
Map<String, Schema> reservedProperties() => {
  r'$schema': {'type': 'string', 'description': 'Where this file is checked.'},
  r'$comment': {'type': 'string', 'description': 'A note for readers.'},
  r'$defs': {
    'type': 'object',
    'description': 'Chunks the objects inside this one can reuse with \$use.',
  },
  r'$use': {
    'type': 'string',
    'description': 'The name of a chunk to put here; keys beside it win.',
  },
};

/// An object with [properties]. A `required` key may come from a chunk, so
/// it is only asked for when the object does not use one.
Schema objectOf(
  Map<String, Schema> properties, {
  List<String> required = const [],
  Object additional = false,
  String? description,
}) => {
  'type': 'object',
  'description': ?description,
  'properties': {...reservedProperties(), ...properties},
  'additionalProperties': additional,
  if (required.isNotEmpty) ...{
    'if': {
      'not': {
        'required': [r'$use'],
      },
    },
    'then': {'required': required},
  },
};

/// A value that may also be a template or a chunk in its place.
Schema orTemplate(Schema schema) => {
  'anyOf': [schema, common('template'), common('use')],
};

/// A value that may be a chunk in its place.
Schema orUse(Schema schema) => {
  'anyOf': [schema, common('use')],
};

/// An object whose every value is [values].
Schema mapOf(Schema values, {String? description}) => {
  'type': 'object',
  'description': ?description,
  'additionalProperties': values,
};

/// A list of [items]; an item may also be `{"$spread": "name"}`.
Schema listOf(Schema items, {String? description}) => {
  'type': 'array',
  'description': ?description,
  'items': {
    'anyOf': [items, common('spread')],
  },
};

Schema text({String? description, String? pattern}) => {
  'type': 'string',
  'description': ?description,
  'pattern': ?pattern,
};

Schema number({String? description}) => {
  'type': 'number',
  'description': ?description,
};

Schema toggle({String? description}) => {
  'type': 'boolean',
  'description': ?description,
};

Schema oneOfText(Iterable<String> choices, {String? description}) => {
  'enum': choices.toList(),
  'description': ?description,
};

/// [schema] as the text of its file.
String schemaText(Schema schema) =>
    '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
