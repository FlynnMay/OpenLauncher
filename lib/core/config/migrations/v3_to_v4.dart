import 'package:openlauncher/core/config/migrations/save_json.dart';

const _popupClose = 'launcher://popups/close';
const _overlayClose = 'launcher://overlay/close';

/// Closing the popup an act fired in is closing the overlay it fired in, which
/// is what the overlay close does when it is told no node.
void popupCloseAsOverlayClose(Json save, Device device) =>
    _closesRewritten(save);

void _closesRewritten(Object? json) {
  switch (json) {
    case final Json map:
      if (map['run'] == _popupClose) map['run'] = _overlayClose;
      map.values.forEach(_closesRewritten);
    case final List<Object?> list:
      list.forEach(_closesRewritten);
  }
}
