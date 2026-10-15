import 'package:openlauncher/core/config/migrations/save_json.dart';

const _addresses = {
  'launchApp': 'os://apps/launch',
  'openAppInfo': 'os://apps/info',
  'uninstallApp': 'os://apps/uninstall',
  'switchInput': 'os://inputs/switch',
  'mediaCommand': 'os://media/command',
  'openTvSettings': 'os://settings/open',
  'changeAccess': 'os://access/change',
  'openSettings': 'launcher://settings/open',
  'checkForUpdate': 'launcher://updates/check',
  'installUpdate': 'launcher://updates/install',
  'newLayer': 'launcher://layers/new',
  'toLayer': 'launcher://layers/raise',
  'closeLayer': 'launcher://layers/close',
  'closePopup': 'launcher://popups/close',
  'setVariable': 'launcher://variables/set',
  'addItem': 'launcher://layout/add',
  'removeItem': 'launcher://layout/remove',
};

/// Operations are named by address: the user's own actions run
/// `os://apps/launch` where they ran `launchApp`.
void operationsByAddress(Json save, Device device) {
  for (final entity in objectsIn(save, 'entities')) {
    if (entity['actions'] case final Json actions) {
      for (final action in actions.values) {
        if (action case {'run': final String run} as Json
            when _addresses.containsKey(run)) {
          action['run'] = _addresses[run];
        }
      }
    }
  }
}
