import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kinds.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';

/// What a thing does when nothing was set for it: a card opens when
/// pressed and shows the quick actions when held, a folder card opens its
/// folder. These are what make a card a button that came ready made.
Triggers usualTriggers(LayoutItem item) => switch (item.kind) {
  ItemKind.card => const {
    Trigger.press: [Act('open')],
    Trigger.hold: [Act('menu')],
  },
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

/// A button that does the action called [name], as the quick actions have
/// them and the editor offers them.
LayoutItem actionButton(String id, ActionKind kind) => LayoutItem(
  id: id,
  kind: ItemKind.widget,
  ref: WidgetKind.button.name,
  options: {'label': kind.label, 'icon': kind.icon},
  on: {
    Trigger.press: [Act(kind.name)],
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
