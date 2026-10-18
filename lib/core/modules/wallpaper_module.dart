import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Rotation intervals: minutes, as text, to their labels.
const wallpaperTurns = {
  '0': 'Stay on the first',
  '1': 'Every minute',
  '5': 'Every 5 minutes',
  '15': 'Every 15 minutes',
  '30': 'Every half hour',
  '60': 'Every hour',
  '180': 'Every 3 hours',
  '1440': 'Every day',
};

/// On a screen's root: its own wallpapers in place of the launcher's. With
/// none it has a plain background.
class WallpaperModule extends ModuleType {
  const WallpaperModule()
    : super(
        'wallpaper',
        'Wallpaper',
        use: ModuleUse.screenRoot,
        // `files` are uploaded files' ids, edited by the module's own editor.
        fields: const [
          Field(
            'every',
            'Change',
            FieldKind.choice,
            defaultValue: '0',
            choices: wallpaperTurns,
          ),
        ],
      );
}

const wallpaperModule = WallpaperModule();

extension NodeWallpaper on Node {
  /// Its wallpapers' file ids, or null if it has no Wallpaper.
  List<String>? get wallpaperFiles => switch (values(wallpaperModule.name)) {
    null => null,
    final values => [
      if (values['files'] case final List<Object?> files)
        ...files.whereType<String>(),
    ],
  };

  /// Minutes per wallpaper; 0 stays on the first.
  int get wallpaperEvery => switch (values(wallpaperModule.name)?['every']) {
    final num minutes => minutes.toInt(),
    final String minutes => int.tryParse(minutes) ?? 0,
    _ => 0,
  };
}
