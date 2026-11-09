import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_setting.dart';

/// Throws [FormatException] unless every value in [settings] (pack id -> key
/// -> value) is for a plain setting of one of [packs] and fits its type.
/// Secrets do not go this way.
void checkPackSettings(List<Pack> packs, Object? settings) {
  if (settings is! Map) throw const FormatException('Expected an object');
  for (final MapEntry(:key, :value) in settings.entries) {
    _checkValuesOf(packs, '$key', value);
  }
}

void _checkValuesOf(List<Pack> packs, String packId, Object? values) {
  if (values is! Map) throw FormatException('Settings of $packId unreadable');
  for (final MapEntry(:key, :value) in values.entries) {
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
