import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/json_expand.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/values/template.dart';

/// The primitives a field is made of.
enum FieldType { text, number, toggle, choice, group }

/// What a text must look like beyond being text.
enum TextFormat { plain, url }

/// A choice whose options come from the web, from `from` in a field's JSON:
/// a [Source] plus how its rows become options. The templates read `row`
/// (one found row), `query` (what was typed, in the address) and `settings`.
@immutable
class FieldOptionsFrom {
  const FieldOptionsFrom(
    this.source, {
    required this.label,
    this.value,
    this.group = '',
    this.where = '',
    this.keep = const {},
    this.on = FindOn.type,
    this.debounce = 300,
    this.minChars,
  });

  final Source source;

  /// How a row is listed; also what a kept map calls itself (`name`).
  final String label;

  /// What choosing a row keeps when [keep] is empty; the label when null.
  final String? value;

  /// A heading to list a row under.
  final String group;

  /// A row is listed only when this reads true.
  final String where;

  /// Other values to keep from a row, each a template. With any, choosing a
  /// row keeps a map: `name` and these.
  final Map<String, String> keep;

  final FindOn on;

  /// Milliseconds of quiet before [FindOn.type] asks.
  final int debounce;

  /// The fewest characters typed before it asks; null asks at one, or at
  /// none when filtering.
  final int? minChars;

  int get leastTyped => minChars ?? (on == FindOn.filter ? 0 : 1);

  static FieldOptionsFrom? fromJson(Object? json) {
    final source = Source.fromJson(json);
    if (source == null || json is! Map) return null;
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    return FieldOptionsFrom(
      source,
      label: label,
      value: json['value'] is String ? json['value'] as String : null,
      group: json['group'] is String ? json['group'] as String : '',
      where: json['where'] is String ? json['where'] as String : '',
      keep: {
        if (json['keep'] case final Map<Object?, Object?> keep)
          for (final MapEntry(:key, :value) in keep.entries)
            if (key is String && key != 'name' && value is String) key: value,
      },
      on: FindOn.values.asNameMap()[json['on']] ?? FindOn.type,
      debounce: switch (json['debounce']) {
        final num pause => pause.toInt().clamp(0, 5000),
        _ => 300,
      },
      minChars: switch (json['minChars']) {
        final num least => least.toInt().clamp(0, 20),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
    ...source.toJson(),
    'label': label,
    'value': ?value,
    if (group.isNotEmpty) 'group': group,
    if (where.isNotEmpty) 'where': where,
    if (keep.isNotEmpty) 'keep': keep,
    if (on != FindOn.type) 'on': on.name,
    if (debounce != 300) 'debounce': debounce,
    'minChars': ?minChars,
  };

  /// How [row] is listed and what choosing it keeps; null for a row that
  /// does not pass [where] or has no label.
  FieldHit? hitFrom(Object? row) {
    Object? lookup(String root) => root == 'row' ? row : null;
    if (where.isNotEmpty && !isTruthy(Template.parse(where).evaluate(lookup))) {
      return null;
    }
    final listed = Template.parse(label).render(lookup).trim();
    if (listed.isEmpty) return null;
    return (
      title: listed,
      group: Template.parse(group).render(lookup).trim(),
      value: keep.isNotEmpty
          ? {
              'name': listed,
              for (final MapEntry(:key, :value) in keep.entries)
                key: Template.parse(value).evaluate(lookup),
            }
          : value == null
          ? listed
          : Template.parse(value!).evaluate(lookup),
    );
  }

  /// Whether [one] is something choosing a row could have kept.
  bool accepts(Object? one) => keep.isNotEmpty
      ? one is Map &&
            '${one['name'] ?? ''}'.isNotEmpty &&
            keep.keys.every(one.containsKey)
      : one is String && one.isNotEmpty || one is num || one is bool;

  @override
  bool operator ==(Object other) =>
      other is FieldOptionsFrom &&
      other.source == source &&
      other.label == label &&
      other.value == value &&
      other.group == group &&
      other.where == where &&
      jsonEquals(other.keep, keep) &&
      other.on == on &&
      other.debounce == debounce &&
      other.minChars == minChars;

  @override
  int get hashCode => Object.hash(source, label, value, on);
}

/// A field below another, or a top one: where it is, as `address.street`, the
/// field itself, and whether it is kept secret (its own say, or a group's).
typedef FieldLeaf = ({String path, FieldSpec spec, bool secret});

/// Premade fields from packs' `fields/` folders, by `<pack>:<name>`. A field
/// of a pack uses one by naming it as its `type`: `address` for its own
/// pack's, `other:address` for another's, and `address.postcode` for a part
/// of a premade group.
@immutable
class FieldLibrary {
  const FieldLibrary([this.premade = const {}]);

  final Map<String, Map<String, Object?>> premade;

  static final _reference = RegExp(
    r'^(?:([a-z0-9][a-z0-9_-]*):)?([a-zA-Z][a-zA-Z0-9_-]*)'
    r'((?:\.[a-zA-Z][a-zA-Z0-9_]*)*)$',
  );

  /// The pack, premade field and parts [reference] names, read from [pack]'s
  /// point of view; null when it is not written as one.
  ({String pack, String name, List<String> parts})? parse(
    String reference,
    String pack,
  ) {
    final match = _reference.firstMatch(reference);
    if (match == null) return null;
    final dotted = match[3]!;
    return (
      pack: match[1] ?? pack,
      name: match[2]!,
      parts: dotted.isEmpty ? const [] : dotted.substring(1).split('.'),
    );
  }
}

/// One field described as data, as a pack writes it in JSON: a [type] and
/// what that primitive takes. Pack settings are these; the editor draws
/// them with [toField].
///
/// A `group` holds other fields by name, and its value is a map of theirs. A
/// pack may name a premade field as the `type` instead; it is read into one
/// of these before it gets here, so nothing below sees a premade field.
@immutable
class FieldSpec {
  const FieldSpec(
    this.type, {
    this.label = '',
    this.help = '',
    this.required = false,
    this.secret = false,
    this.defaultValue,
    this.visible = '',
    this.span = 1,
    this.placeholder = '',
    this.multiline = false,
    this.pattern,
    this.minLength,
    this.maxLength,
    this.format = TextFormat.plain,
    this.min,
    this.max,
    this.step = 1,
    this.decimal = false,
    this.options = const {},
    this.from,
    this.look,
    this.unset,
    this.multiple = false,
    this.minChoices,
    this.maxChoices,
    this.fields = const {},
    this.columns = 1,
  });

  final FieldType type;
  final String label, help;

  /// Whether the pack does nothing until it has a value.
  final bool required;

  /// Kept apart on the TV, never sent to the editor, and censored there: the
  /// field only says whether it is set. Of any [type]; on a group, of every
  /// field in it.
  final bool secret;

  /// The value when none is saved; a secret has none.
  final Object? defaultValue;

  /// A template over `values`, the fields beside this one, and `root`, the
  /// whole form; the field applies only when it reads true. Empty always
  /// applies.
  final String visible;

  /// How many of its group's columns it takes up.
  final int span;

  // Text.
  final String placeholder;
  final bool multiline;
  final String? pattern;
  final int? minLength, maxLength;
  final TextFormat format;

  // Number. A bound left out is open.
  final num? min, max;
  final num step;
  final bool decimal;

  // Choice.
  /// Static options, value -> label.
  final Map<String, String> options;

  /// Options from the web; when given, [options] is ignored.
  final FieldOptionsFrom? from;

  /// Null picks a look by how many options there are.
  final ChoiceLook? look;

  /// Label of "none chosen", for a single choice that may be left unmade.
  final String? unset;

  /// Several may be chosen; the value is a list.
  final bool multiple;
  final int? minChoices, maxChoices;

  // Group.
  /// The fields in it, by name, in the order they are shown.
  final Map<String, FieldSpec> fields;

  /// How many units wide a row is; each field takes its [span] of them and
  /// a row wraps when the next would not fit.
  final int columns;

  static const _singleLooks = {
    ChoiceLook.dropdown,
    ChoiceLook.radio,
    ChoiceLook.segmented,
  };

  /// The most columns or span, and how deep premade fields may build on one
  /// another.
  static const _widest = 12, _deepest = 8;

  static final _name = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  /// Reads [json] as written in [pack] (whose premade fields are bare
  /// names), with [library] for the premade fields it may name.
  static FieldSpec? fromJson(
    Object? json, {
    FieldLibrary library = const FieldLibrary(),
    String pack = '',
  }) {
    final plain = _expand(json, library, pack, 0);
    return plain == null ? null : _read(plain, useDefault: true);
  }

  /// [json] with every premade field in it, and every flat `a.b` name,
  /// written out as the primitive and groups they stand for; null when it
  /// cannot be.
  static Map<String, Object?>? _expand(
    Object? json,
    FieldLibrary library,
    String pack,
    int depth,
  ) {
    if (json is! Map || json['type'] is! String || depth > _deepest) {
      return null;
    }
    final named = json['type'] as String;
    final plain = FieldType.values.asNameMap()[named] != null;
    final expanded = plain
        ? {...jsonStringKeyed(json)}
        : _premade(jsonStringKeyed(json), named, library, pack, depth);
    if (expanded == null) return null;
    if (expanded['type'] == FieldType.group.name) {
      expanded['fields'] = _expandedFields(
        expanded['fields'],
        library,
        pack,
        depth,
      );
    }
    return expanded;
  }

  static Map<String, Object?> _expandedFields(
    Object? fields,
    FieldLibrary library,
    String pack,
    int depth,
  ) => {
    if (fields is Map)
      for (final MapEntry(:key, :value) in expandNames(fields).entries)
        if (key is String) key: ?_expand(value, library, pack, depth + 1),
  };

  /// The premade field [reference] names, filled in with the parameters in
  /// [usage] and written over by the rest of it.
  static Map<String, Object?>? _premade(
    Map<String, Object?> usage,
    String reference,
    FieldLibrary library,
    String pack,
    int depth,
  ) {
    final named = library.parse(reference, pack);
    final file = named == null
        ? null
        : library.premade['${named.pack}:${named.name}'];
    if (named == null || file == null || file['extends'] is! String) {
      return null;
    }
    final base = _expand(
      {..._withParameters(file, usage['params']), 'type': file['extends']},
      library,
      named.pack,
      depth + 1,
    );
    final part = base == null ? null : _partOf(base, named.parts);
    if (part == null) return null;
    return _overlaid(part, usage, library, pack, depth);
  }

  /// The field at [parts] below [field], or [field] without any.
  static Map<String, Object?>? _partOf(
    Map<String, Object?> field,
    List<String> parts,
  ) {
    var found = field;
    for (final part in parts) {
      final inside = found['fields'];
      if (inside is! Map || inside[part] is! Map) return null;
      found = jsonStringKeyed(inside[part]);
    }
    return found;
  }

  /// [premade] as a file wrote it, minus what only a premade field has, its
  /// `{{param.x}}` filled from what [given] says and what it declares.
  static Map<String, Object?> _withParameters(
    Map<String, Object?> premade,
    Object? given,
  ) {
    final declared = premade[r'$params'];
    final values = {
      if (declared is Map)
        for (final MapEntry(:key, :value) in declared.entries)
          if (key is String)
            key: given is Map && given.containsKey(key)
                ? given[key]
                : value is Map
                ? value['default']
                : value,
    };
    final body = {...premade}
      ..remove(r'$params')
      ..remove('extends');
    return jsonStringKeyed(fillParameters(body, values));
  }

  /// [base] with what [usage] says written over it: every key but `type` and
  /// `params`, and `fields` a field at a time.
  static Map<String, Object?> _overlaid(
    Map<String, Object?> base,
    Map<String, Object?> usage,
    FieldLibrary library,
    String pack,
    int depth,
  ) {
    final over = {...usage}
      ..remove('type')
      ..remove('params');
    final result = {...base, ...over};
    if (base['fields'] is Map && over['fields'] is Map) {
      result['fields'] = _fieldsOverlaid(
        base['fields'] as Map,
        over['fields'] as Map,
        library,
        pack,
        depth,
      );
    }
    return result;
  }

  static Map<String, Object?> _fieldsOverlaid(
    Map<Object?, Object?> base,
    Map<Object?, Object?> over,
    FieldLibrary library,
    String pack,
    int depth,
  ) {
    final result = {...jsonStringKeyed(base)};
    for (final MapEntry(:key, :value) in expandNames(over).entries) {
      if (key is! String || value is! Map) continue;
      final before = result[key];
      result[key] = value['type'] is String
          ? _expand(value, library, pack, depth + 1)
          : before is Map
          ? _overlaid(
              jsonStringKeyed(before),
              jsonStringKeyed(value),
              library,
              pack,
              depth,
            )
          : value;
    }
    return result..removeWhere((_, field) => field == null);
  }

  /// [json] with each flat name, `address.street`, put into the group
  /// `address` as `street`, making the group, where its first flat name is,
  /// if it is not there. Names are split at the first dot, so a deeper one is
  /// split again inside.
  static Map<Object?, Object?> expandNames(Map<Object?, Object?> json) {
    final parts = <String, Map<Object?, Object?>>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is String && key.contains('.')) {
        final dot = key.indexOf('.');
        (parts[key.substring(0, dot)] ??= {})[key.substring(dot + 1)] = value;
      }
    }
    final result = <Object?, Object?>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is String && key.contains('.')) {
        final group = key.substring(0, key.indexOf('.'));
        if (!json.containsKey(group)) {
          result.putIfAbsent(group, () => _withParts(null, parts[group]!));
        }
      } else {
        result[key] = _withParts(value, parts[key]);
      }
    }
    return result;
  }

  /// The group [before], or a new one, with [parts] among its fields.
  static Object? _withParts(Object? before, Map<Object?, Object?>? parts) {
    if (parts == null) return before;
    if (before == null) {
      return {'type': FieldType.group.name, 'fields': parts};
    }
    if (before is! Map) return before;
    final inside = before['fields'];
    return {
      ...before,
      'fields': {if (inside is Map) ...inside, ...parts},
    };
  }

  /// Reads a spec written out in full: no premade fields, no flat names.
  static FieldSpec? _read(
    Map<String, Object?> json, {
    required bool useDefault,
  }) {
    final type = FieldType.values.asNameMap()[json['type']];
    if (type == null) return null;
    final multiple = json['multiple'] == true;
    final secret = json['secret'] == true;
    final spec = FieldSpec(
      type,
      label: _text(json['label']),
      help: _text(json['help']),
      required: json['required'] == true,
      secret: secret,
      defaultValue: secret || !useDefault || type == FieldType.group
          ? null
          : json['default'],
      visible: _text(json['visible']),
      span: _count(json['span']),
      placeholder: _text(json['placeholder']),
      multiline: json['multiline'] == true,
      pattern: json['pattern'] is String ? json['pattern'] as String : null,
      minLength: _whole(json['minLength']),
      maxLength: _whole(json['maxLength']),
      format: TextFormat.values.asNameMap()[json['format']] ?? TextFormat.plain,
      min: json['min'] is num ? json['min'] as num : null,
      max: json['max'] is num ? json['max'] as num : null,
      step: switch (json['step']) {
        final num step when step > 0 => step,
        _ => 1,
      },
      decimal: json['decimal'] == true,
      options: _options(json['options']),
      from: FieldOptionsFrom.fromJson(json['from']),
      look: _lookOf(json['as'], multiple),
      unset: json['unset'] is String ? json['unset'] as String : null,
      multiple: multiple,
      minChoices: _whole(json['minChoices']),
      maxChoices: _whole(json['maxChoices']),
      fields: type == FieldType.group ? _readFields(json['fields']) : const {},
      columns: _count(json['columns']),
    );
    if (!spec._usable) return null;
    final fits = spec.defaultValue == null || spec.accepts(spec.defaultValue);
    return fits ? spec : _read(json, useDefault: false);
  }

  static Map<String, FieldSpec> _readFields(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String &&
            _name.hasMatch(key) &&
            value is Map<String, Object?>)
          key: ?_read(value, useDefault: true),
  };

  static String _text(Object? json) => json is String ? json : '';

  static int? _whole(Object? json) => json is num ? json.toInt() : null;

  /// A column count or span: at least one, at most [_widest].
  static int _count(Object? json) =>
      json is num ? json.toInt().clamp(1, _widest) : 1;

  /// A look is only for the kind of choice it suits.
  static ChoiceLook? _lookOf(Object? name, bool multiple) {
    final look = switch (name) {
      'dropdown' when multiple => ChoiceLook.multiDropdown,
      _ => ChoiceLook.values.asNameMap()[name],
    };
    return look == null || _singleLooks.contains(look) == !multiple
        ? look
        : null;
  }

  /// Options as a map of value -> label, or a list of values that are their
  /// own labels.
  static Map<String, String> _options(Object? json) => switch (json) {
    final Map<Object?, Object?> labelled => {
      for (final MapEntry(:key, :value) in labelled.entries)
        if (key is String) key: '$value',
    },
    final List<Object?> values => {
      for (final value in values)
        if (value is String) value: value,
    },
    _ => const {},
  };

  bool get _usable {
    if (type == FieldType.choice && options.isEmpty && from == null) {
      return false;
    }
    if (type == FieldType.group && fields.isEmpty) return false;
    if (pattern != null && !_compiles(pattern!)) return false;
    final low = min, high = max;
    return low == null || high == null || low <= high;
  }

  static bool _compiles(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } on FormatException {
      return false;
    }
  }

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (label.isNotEmpty) 'label': label,
    if (help.isNotEmpty) 'help': help,
    if (required) 'required': true,
    if (secret) 'secret': true,
    'default': ?defaultValue,
    if (visible.isNotEmpty) 'visible': visible,
    if (span != 1) 'span': span,
    if (placeholder.isNotEmpty) 'placeholder': placeholder,
    if (multiline) 'multiline': true,
    'pattern': ?pattern,
    'minLength': ?minLength,
    'maxLength': ?maxLength,
    if (format != TextFormat.plain) 'format': format.name,
    'min': ?min,
    'max': ?max,
    if (step != 1) 'step': step,
    if (decimal) 'decimal': true,
    if (type == FieldType.choice) ...{
      if (from == null) 'options': options,
      'from': ?from?.toJson(),
      if (look != null)
        'as': look == ChoiceLook.multiDropdown ? 'dropdown' : look!.name,
      'unset': ?unset,
      if (multiple) 'multiple': true,
      'minChoices': ?minChoices,
      'maxChoices': ?maxChoices,
    },
    if (type == FieldType.group) ...{
      if (columns != 1) 'columns': columns,
      'fields': {
        for (final MapEntry(:key, :value) in fields.entries)
          key: value.toJson(),
      },
    },
  };

  /// Whether [value] is a usable value of this field.
  bool accepts(Object? value) => switch (type) {
    FieldType.text => value is String && _textFits(value),
    FieldType.number =>
      value is num &&
          (min == null || value >= min!) &&
          (max == null || value <= max!),
    FieldType.toggle => value is bool,
    FieldType.choice => multiple ? _severalFit(value) : _oneFits(value),
    FieldType.group => value is Map && value.entries.every(_partFits),
  };

  /// A part of a group's value fits when it names a field there that is not
  /// kept secret, which is never in a value, and that accepts it.
  bool _partFits(MapEntry<Object?, Object?> part) {
    final field = fields[part.key];
    return !secret &&
        field != null &&
        !field.secret &&
        field.accepts(part.value);
  }

  bool _textFits(String text) {
    if (text.isEmpty) return true;
    if (minLength != null && text.length < minLength!) return false;
    if (maxLength != null && text.length > maxLength!) return false;
    if (pattern != null && !RegExp(pattern!).hasMatch(text)) return false;
    return format != TextFormat.url || _isWebAddress(text);
  }

  static bool _isWebAddress(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  bool _oneFits(Object? one) => from != null
      ? from!.accepts(one)
      : one is String && options.containsKey(one);

  bool _severalFit(Object? value) =>
      value is List &&
      (minChoices == null || value.length >= minChoices!) &&
      (maxChoices == null || value.length <= maxChoices!) &&
      value.every(_oneFits);

  /// Every field in this one that holds a value of its own: itself, or each
  /// of a group's, by path from [path]. A group's secret is on all of them.
  Iterable<FieldLeaf> leaves(String path, {bool secretAbove = false}) sync* {
    final hidden = secretAbove || secret;
    if (type != FieldType.group) {
      yield (path: path, spec: this, secret: hidden);
      return;
    }
    for (final MapEntry(:key, value: field) in fields.entries) {
      yield* field.leaves('$path.$key', secretAbove: hidden);
    }
  }

  /// The value at [path], `address.street`, in [values]; null if none.
  static Object? valueAt(Object? values, String path) {
    Object? found = values;
    for (final part in path.split('.')) {
      if (found is! Map) return null;
      found = found[part];
    }
    return found;
  }

  /// A secret's value as the text the TV keeps: text as it is, anything else
  /// as JSON (a number or a tick as written, a list as a list).
  static String storedAs(Object value) =>
      value is String ? value : jsonEncode(value);

  /// Whether [value] counts as nothing given, for a required field.
  static bool isBlank(Object? value) =>
      value == null || value == '' || value is List && value.isEmpty;

  /// Whether the field applies, given the [values] beside it and the form's
  /// whole value, [root], when that is not the same.
  bool shows(Map<String, Object?> values, {Map<String, Object?>? root}) =>
      visible.isEmpty ||
      isTruthy(
        Template.parse(visible).evaluate(
          (name) => switch (name) {
            'values' => values,
            'root' => root ?? values,
            _ => null,
          },
        ),
      );

  /// What a chosen option is called: a kept map by its `name`.
  static String nameOf(Object? chosen) => switch (chosen) {
    {'name': final Object name} => '$name',
    _ => valueText(chosen),
  };

  /// How the choice is drawn: as asked, else by how many options it has.
  ChoiceLook get _drawnAs =>
      look ??
      (multiple
          ? (options.length <= 6 ? ChoiceLook.checks : ChoiceLook.multiDropdown)
          : (options.length <= 4 && unset == null
                ? ChoiceLook.radio
                : ChoiceLook.dropdown));

  /// The editor's field for this one under [key], inside the group at path
  /// [above]. [findAt] answers a choice from the web and [secretAt] says
  /// about a secret, each given the field's whole path.
  Field toField(
    String key, {
    String above = '',
    bool secretAbove = false,
    Future<List<FieldHit>> Function(String path, String text)? findAt,
    FieldSecret? Function(String path)? secretAt,
  }) {
    final path = above.isEmpty ? key : '$above.$key';
    final hidden = secretAbove || secret;
    return Field(
      key,
      '${label.isEmpty ? key : label}${required ? ' *' : ''}',
      switch (type) {
        FieldType.text => FieldKind.text,
        FieldType.number => FieldKind.number,
        FieldType.toggle => FieldKind.toggle,
        FieldType.choice => FieldKind.choice,
        FieldType.group => FieldKind.group,
      },
      defaultValue: defaultValue,
      choices: options,
      // A number left open can still be typed into.
      min: min?.round() ?? -1000000,
      max: max?.round() ?? 1000000,
      step: step.round().clamp(1, 1 << 30),
      decimal: decimal,
      unset: unset,
      whenRoot: visible.isEmpty
          ? null
          : (values, root) => shows(values, root: root),
      find: from == null || findAt == null
          ? null
          : (text) => findAt(path, text),
      secret: hidden && type != FieldType.group ? secretAt?.call(path) : null,
      placeholder: placeholder,
      multiline: multiline,
      help: help,
      fits: type == FieldType.text ? _textFits : null,
      look: _drawnAs,
      multiple: multiple,
      remote: from == null
          ? null
          : FieldFinding(
              on: from!.on,
              debounce: Duration(milliseconds: from!.debounce),
              minChars: from!.leastTyped,
            ),
      maxChoices: maxChoices,
      group: [
        for (final MapEntry(key: name, value: field) in fields.entries)
          field.toField(
            name,
            above: path,
            secretAbove: hidden,
            findAt: findAt,
            secretAt: secretAt,
          ),
      ],
      columns: columns,
      span: span,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FieldSpec && jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(type, label, required);
}
