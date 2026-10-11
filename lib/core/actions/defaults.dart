import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/actions/action_kinds.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';

/// What a thing does when neither it nor its prefab says: what opens a
/// folder opens it, which only the item can know. What an instance of a
/// prefab does is the prefab's to say.
Triggers usualTriggers(LayoutItem item) => switch (item.kind) {
  ItemKind.panel => {
    Trigger.press: [
      Act('panel', {panelArg: item.ref}),
    ],
  },
  _ => const {},
};

/// What [item] does: what was set for it, and the usual for every trigger
/// nothing was set for.
Triggers triggersOf(LayoutItem item) => {...usualTriggers(item), ...item.on};

/// A button that does [kind], as the quick actions have them and the
/// editor offers them: to whatever it is set off from, or to [entity] by
/// its id.
LayoutItem actionButton(String id, ActionKind kind, {String? entity}) =>
    LayoutItem(
      id: id,
      kind: ItemKind.widget,
      ref: WidgetKind.button.name,
      options: {'label': kind.label, 'icon': kind.icon},
      on: {
        Trigger.press: [
          Act(kind.name, {entityArg: ?entity}),
        ],
      },
    );

/// The names of the actions the quick actions start with, in order.
const usualMenu = ['open', 'info', 'forceStop', 'uninstall', 'remove'];

/// The quick actions as they are until the user arranges them: a popup
/// like any folder, holding a button for each action.
Panel usualMenuPanel() => Panel(
  id: Layout.menuId,
  size: PopupSize.small,
  root: Pane(
    id: Panel.rootId(Layout.menuId),
    columns: 1,
    rowHeight: 40,
    spacing: 4,
    items: [
      for (final name in usualMenu)
        if (actionKind(name) case final kind?)
          actionButton('${Layout.menuId}-${kind.name.toLowerCase()}', kind),
    ],
  ),
);
