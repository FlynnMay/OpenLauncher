import 'package:openlauncher_domain/config/migrations/save_json.dart';

const _systemPack = 'system';
const _oldWeatherPrefab = 'system:weather';

/// Weather is a source of the System pack now: the place the user chose is
/// that pack's location setting, and a copy of the old prefab, which reads
/// an entity that is gone, is dropped for the pack's own.
void weatherAsPackData(Json save, Device device) {
  _placeAsLocationSetting(save);
  _oldWeatherCopyDropped(save);
}

// ---------------------------------------------------------------- Private

void _placeAsLocationSetting(Json save) {
  final place = save.remove('place');
  if (place is! Json) return;
  final settings = jsonObject(save['packSettings'] ?? <String, Object?>{});
  final system = jsonObject(settings[_systemPack] ?? <String, Object?>{});
  system.putIfAbsent('location', () => place);
  settings[_systemPack] = system;
  save['packSettings'] = settings;
}

void _oldWeatherCopyDropped(Json save) {
  if (save['prefabs'] case final List<Object?> prefabs) {
    prefabs.removeWhere(_readsOldWeatherEntity);
  }
}

bool _readsOldWeatherEntity(Object? prefab) {
  if (prefab is! Json || prefab['id'] != _oldWeatherPrefab) return false;
  final variables = jsonObject(
    jsonObject(jsonObject(prefab['root'])['modules'])['variables'],
  );
  return jsonObject(variables['source'])['value'] == _oldWeatherPrefab;
}
