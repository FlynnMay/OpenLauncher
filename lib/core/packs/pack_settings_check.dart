import 'dart:convert';

import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_setting.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';

/// Throws [FormatException] unless every value in [settings] (pack id -> key
/// -> value) is for a plain setting of one of [packs] and fits its type.
/// Secrets do not go this way. A value that is as it was in [saved] is not
/// checked: a pack update that drops a setting must not stop the others from
/// being saved.
void checkPackSettings(List<Pack> packs, Object? settings, {Object? saved}) {
  if (settings is! Map) throw const FormatException('Expected an object');
  for (final MapEntry(:key, :value) in settings.entries) {
    _checkValuesOf(packs, '$key', value, saved is Map ? saved[key] : null);
  }
}

void _checkValuesOf(
  List<Pack> packs,
  String packId,
  Object? values,
  Object? saved,
) {
  if (values is! Map) throw FormatException('Settings of $packId unreadable');
  for (final MapEntry(:key, :value) in values.entries) {
    if (saved is Map &&
        saved.containsKey(key) &&
        jsonEncode(saved[key]) == jsonEncode(value)) {
      continue;
    }
    final setting = settingOf(packs, packId, '$key');
    if (setting == null || setting.secret || !setting.accepts(value)) {
      throw FormatException('Not a setting of $packId: $key');
    }
  }
}

/// The setting [key] of the pack [packId] among [packs], if there is one.
PackSetting? settingOf(List<Pack> packs, String? packId, String? key) {
  for (final pack in packs) {
    if (pack.id == packId) {
      return pack.settings.where((setting) => setting.key == key).firstOrNull;
    }
  }
  return null;
}

/// The field at [path], `address.street`, among the settings of the pack
/// [packId] in [packs], if there is one.
FieldLeaf? fieldOf(List<Pack> packs, String? packId, String? path) {
  if (path == null) return null;
  for (final pack in packs) {
    if (pack.id == packId) return pack.fieldAt(path);
  }
  return null;
}
