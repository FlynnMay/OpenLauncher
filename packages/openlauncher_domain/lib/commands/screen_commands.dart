import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/config_commands.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/layout/screen_copy.dart';

const noSuchScreen = 'There is no such screen.';

/// An empty screen. [id] is wanted, not promised; [name] is its label.
class AddScreen extends LayoutCommand {
  const AddScreen({this.id, this.name = ''});

  factory AddScreen.fromJson(Json json) => AddScreen(
    id: jsonOptional<String>(json, 'id'),
    name: jsonOptional<String>(json, 'name') ?? '',
  );

  static const typeName = 'screen.add';

  final String? id;
  final String name;

  @override
  String get type => typeName;

  /// The id the screen gets in [layout].
  String idIn(Layout layout) =>
      freeId(id ?? slugOf(name, 'screen'), layout.itemIds);

  @override
  Layout apply(Layout layout) {
    final empty = Screen.empty(idIn(layout));
    return layout.copyWith(
      screens: [
        ...layout.screens,
        empty.withRoot(empty.root.copyWith(name: name)),
      ],
    );
  }

  @override
  LayoutCommand inverse(Layout before) => RemoveScreen(idIn(before));

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'name': name,
  };
}

class RemoveScreen extends LayoutCommand {
  const RemoveScreen(this.id);

  factory RemoveScreen.fromJson(Json json) =>
      RemoveScreen(jsonRequired<String>(json, 'id'));

  static const typeName = 'screen.remove';

  final String id;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (layout.screen(id) == null) throw const CommandRefused(noSuchScreen);
    if (layout.screens.length < 2) {
      throw const CommandRefused('The last screen stays.');
    }
    return layout.copyWith(
      screens: [
        for (final screen in layout.screens)
          if (screen.id != id) screen,
      ],
    );
  }

  @override
  LayoutCommand inverse(Layout before) => RestoreScreen(
    before.screen(id) ?? (throw const CommandRefused(noSuchScreen)),
    before.screens.indexWhere((screen) => screen.id == id),
  );

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id};
}

/// A screen put back as it was, at place [index] among the screens.
class RestoreScreen extends LayoutCommand {
  const RestoreScreen(this.screen, this.index);

  factory RestoreScreen.fromJson(Json json) => RestoreScreen(
    Screen.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'screen')),
    jsonOptional<int>(json, 'index') ?? 0,
  );

  static const typeName = 'screen.restore';

  final Screen screen;
  final int index;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (layout.screen(screen.id) != null) {
      throw CommandRefused('Screen "${screen.id}" is already there.');
    }
    final screens = [...layout.screens];
    screens.insert(index.clamp(0, screens.length), screen);
    return layout.copyWith(screens: screens);
  }

  @override
  LayoutCommand inverse(Layout before) => RemoveScreen(screen.id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'screen': screen.toJson(),
    'index': index,
  };
}

/// Gives a screen another label.
class RenameScreen extends LayoutCommand {
  const RenameScreen(this.id, this.name);

  factory RenameScreen.fromJson(Json json) => RenameScreen(
    jsonRequired<String>(json, 'id'),
    jsonOptional<String>(json, 'name') ?? '',
  );

  static const typeName = 'screen.rename';

  final String id;
  final String name;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    if (layout.screen(id) == null) throw const CommandRefused(noSuchScreen);
    return layout.copyWith(
      screens: [
        for (final screen in layout.screens)
          screen.id == id
              ? screen.withRoot(screen.root.copyWith(name: name))
              : screen,
      ],
    );
  }

  @override
  LayoutCommand inverse(Layout before) => RenameScreen(
    id,
    (before.screen(id) ?? (throw const CommandRefused(noSuchScreen))).root.name,
  );

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id, 'name': name};
}

/// Sets which screen the launcher opens on, and whether it opens on the one
/// shown last instead. A value left out stays as it is.
class SetStartup extends LayoutCommand {
  const SetStartup({this.screenId, this.remember});

  factory SetStartup.fromJson(Json json) => SetStartup(
    screenId: jsonOptional<String>(json, 'screen'),
    remember: jsonOptional<bool>(json, 'remember'),
  );

  static const typeName = 'screen.startup';

  final String? screenId;
  final bool? remember;

  @override
  String get type => typeName;

  @override
  Layout apply(Layout layout) {
    final id = screenId;
    if (id != null && layout.screen(id) == null) {
      throw const CommandRefused(noSuchScreen);
    }
    return layout.copyWith(
      startup: Startup(
        id ?? layout.startup.screen,
        remember: remember ?? layout.startup.remember,
      ),
    );
  }

  @override
  LayoutCommand inverse(Layout before) => SetStartup(
    screenId: before.startup.screen,
    remember: before.startup.remember,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (screenId != null) 'screen': screenId,
    if (remember != null) 'remember': remember,
  };
}

/// A copy of a screen, next to it, with new nodes. Pictures set on a node go
/// with its copy.
class DuplicateScreen extends Command {
  const DuplicateScreen(this.id);

  factory DuplicateScreen.fromJson(Json json) =>
      DuplicateScreen(jsonRequired<String>(json, 'id'));

  static const typeName = 'screen.duplicate';
  static const _pictureSettings = ['iconOverrides', 'iconSources'];

  final String id;

  @override
  String get type => typeName;

  /// The id the copy gets in [layout].
  String copyIdIn(Layout layout) => freeId(id, layout.itemIds);

  @override
  Document edit(Document document) {
    final layout = document.layout;
    final original =
        layout.screen(id) ?? (throw const CommandRefused(noSuchScreen));
    final (:screen, :renamed) = original.copied(copyIdIn(layout));
    return document.copyWith(
      layout: layout.copyWith(
        screens: [
          for (final one in layout.screens) ...[one, if (one.id == id) screen],
        ],
      ),
      settings: {
        ...document.settings,
        for (final setting in _pictureSettings)
          if (document.settings[setting] case final Map<Object?, Object?> set)
            setting: _picturesCopied(set, renamed),
      },
    );
  }

  @override
  Command undoing(Document before) => Batch([
    RemoveScreen(copyIdIn(before.layout)),
    SetConfig({
      for (final setting in _pictureSettings)
        if (before.settings.containsKey(setting))
          setting: before.settings[setting],
    }),
  ]);

  /// [pictures] with the entries of the nodes in [renamed] repeated for their
  /// new ids.
  static Map<Object?, Object?> _picturesCopied(
    Map<Object?, Object?> pictures,
    Map<String, String> renamed,
  ) => {
    ...pictures,
    for (final MapEntry(:key, :value) in renamed.entries)
      Layout.pictureKey(value): ?pictures[Layout.pictureKey(key)],
  };

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id};
}

/// The commands about screens, by the name they go by in JSON.
final Map<String, CommandReader> screenCommandReaders = {
  AddScreen.typeName: AddScreen.fromJson,
  RemoveScreen.typeName: RemoveScreen.fromJson,
  RestoreScreen.typeName: RestoreScreen.fromJson,
  RenameScreen.typeName: RenameScreen.fromJson,
  SetStartup.typeName: SetStartup.fromJson,
  DuplicateScreen.typeName: DuplicateScreen.fromJson,
};
