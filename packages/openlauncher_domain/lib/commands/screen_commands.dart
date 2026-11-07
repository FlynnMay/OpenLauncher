import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';

const noSuchScreen = 'There is no such screen.';

/// An empty screen. [id] is wanted, not promised; [name] is its label.
class AddScreen extends Command {
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
  Command inverse(Layout before) => RemoveScreen(idIn(before));

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'name': name,
  };
}

class RemoveScreen extends Command {
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
  Command inverse(Layout before) => RestoreScreen(
    before.screen(id) ?? (throw const CommandRefused(noSuchScreen)),
    before.screens.indexWhere((screen) => screen.id == id),
  );

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id};
}

/// A screen put back as it was, at place [index] among the screens.
class RestoreScreen extends Command {
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
  Command inverse(Layout before) => RemoveScreen(screen.id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'screen': screen.toJson(),
    'index': index,
  };
}

/// The commands about screens, by the name they go by in JSON.
final Map<String, CommandReader> screenCommandReaders = {
  AddScreen.typeName: AddScreen.fromJson,
  RemoveScreen.typeName: RemoveScreen.fromJson,
  RestoreScreen.typeName: RestoreScreen.fromJson,
};
