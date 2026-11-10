import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/values/template.dart';

/// The primitives a field is made of.
enum FieldType { text, number, toggle, choice, secret }

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

/// One field described as data, as a pack writes it in JSON: a [type] and
/// what that primitive takes. Pack settings are these; the editor draws
/// them with [toField].
@immutable
class FieldSpec {
  const FieldSpec(
    this.type, {
    this.label = '',
    this.help = '',
    this.required = false,
    this.defaultValue,
    this.visible = '',
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
  });

  final FieldType type;
  final String label, help;

  /// Whether the pack does nothing until it has a value.
  final bool required;

  /// The value when none is saved.
  final Object? defaultValue;

  /// A template over `values`, the sibling fields' values; the field applies
  /// only when it reads true. Empty always applies.
  final String visible;

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

  bool get secret => type == FieldType.secret;

  static const _singleLooks = {
    ChoiceLook.dropdown,
    ChoiceLook.radio,
    ChoiceLook.segmented,
  };

  static FieldSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = FieldType.values.asNameMap()[json['type']];
    if (type == null) return null;
    final multiple = json['multiple'] == true;
    final spec = FieldSpec(
      type,
      label: _text(json['label']),
      help: _text(json['help']),
      required: json['required'] == true,
      defaultValue: json['default'],
      visible: _text(json['visible']),
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
    );
    return spec._usable ? spec.withUsableDefault : null;
  }

  static String _text(Object? json) => json is String ? json : '';

  static int? _whole(Object? json) => json is num ? json.toInt() : null;

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

  /// This without a default that does not fit it.
  FieldSpec get withUsableDefault =>
      defaultValue == null || accepts(defaultValue)
      ? this
      : FieldSpec(
          type,
          label: label,
          help: help,
          required: required,
          visible: visible,
          placeholder: placeholder,
          multiline: multiline,
          pattern: pattern,
          minLength: minLength,
          maxLength: maxLength,
          format: format,
          min: min,
          max: max,
          step: step,
          decimal: decimal,
          options: options,
          from: from,
          look: look,
          unset: unset,
          multiple: multiple,
          minChoices: minChoices,
          maxChoices: maxChoices,
        );

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (label.isNotEmpty) 'label': label,
    if (help.isNotEmpty) 'help': help,
    if (required) 'required': true,
    'default': ?defaultValue,
    if (visible.isNotEmpty) 'visible': visible,
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
  };

  /// Whether [value] is a usable value of this field.
  bool accepts(Object? value) => switch (type) {
    FieldType.text => value is String && _textFits(value),
    FieldType.secret => value is String,
    FieldType.number =>
      value is num &&
          (min == null || value >= min!) &&
          (max == null || value <= max!),
    FieldType.toggle => value is bool,
    FieldType.choice => multiple ? _severalFit(value) : _oneFits(value),
  };

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

  /// Whether [value] counts as nothing given, for a required field.
  static bool isBlank(Object? value) =>
      value == null || value == '' || value is List && value.isEmpty;

  /// Whether the field applies, given its siblings' [values].
  bool shows(Map<String, Object?> values) =>
      visible.isEmpty ||
      isTruthy(
        Template.parse(visible)
            .evaluate((root) => root == 'values' ? values : null),
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

  /// The editor's field for this one under [key]. [find] answers a choice
  /// from the web; [secretState] says about a secret.
  Field toField(
    String key, {
    String? labelled,
    Future<List<FieldHit>> Function(String text)? find,
    FieldSecret? secretState,
  }) => Field(
    key,
    labelled ?? (label.isEmpty ? key : label),
    switch (type) {
      FieldType.text => FieldKind.text,
      FieldType.number => FieldKind.number,
      FieldType.toggle => FieldKind.toggle,
      FieldType.choice => FieldKind.choice,
      FieldType.secret => FieldKind.secret,
    },
    defaultValue: defaultValue,
    choices: options,
    // A number left open can still be typed into.
    min: min?.round() ?? -1000000,
    max: max?.round() ?? 1000000,
    step: step.round().clamp(1, 1 << 30),
    decimal: decimal,
    unset: unset,
    when: visible.isEmpty ? null : shows,
    find: from == null ? null : find,
    secret: secretState,
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
  );

  @override
  bool operator ==(Object other) =>
      other is FieldSpec && jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(type, label, required);
}
