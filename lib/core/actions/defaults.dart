import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/actions/action_kinds.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// What a panel does when its pane does not say: a sidebar that is
/// revealed is put on a layer of its own above the home screen, as is a
/// folder, and the layer goes when it is hidden. These are their
/// ready-made rules, there to be changed like any other.
Triggers usualPanelTriggers(Panel panel) => switch (panel.kind) {
  PanelKind.sidebar => const {
    Trigger.reveal: [Act('newLayer'), Act('toLayer')],
    Trigger.hide: [Act('closeLayer')],
  },
  // A folder hovers over the screen: a layer that darkens what is under
  // it and keeps the focus. One set to open in place needs no layer.
  PanelKind.popup when panel.position != PopupPosition.inline => const {
    Trigger.reveal: [
      Act('newLayer', {'dim': 0.54, 'modal': true}),
      Act('toLayer'),
    ],
    Trigger.hide: [Act('closeLayer')],
  },
  _ => const {},
};

/// What [panel] does: what its pane says, and the usual for every trigger
/// it says nothing of.
Triggers panelTriggersOf(Panel panel) => {
  ...usualPanelTriggers(panel),
  ...panel.root.on,
};

/// A button that does [kind], as the quick actions have them and the
/// editor offers them: to whatever it is set off from, or to [entity] by
/// its id.
LayoutItem actionButton(String id, ActionKind kind, {String? entity}) =>
    LayoutItem(
      id: id,
      kind: ItemKind.component,
      ref: ComponentKind.button.name,
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
