import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout_model.dart';

/// A layout item together with what it shows.
@immutable
sealed class Entry {
  const Entry(this.item);

  final LayoutItem item;
}

class CardEntry extends Entry {
  const CardEntry(super.item, this.card);

  final LauncherCard card;
}

/// A card that opens a popup: a folder, or any other panel.
class PanelEntry extends Entry {
  const PanelEntry(
    super.item,
    this.panel, {
    this.preview = const [],
    this.icon,
  });

  final Panel panel;

  /// The first few cards inside, for drawing the folder's face.
  final List<LauncherCard> preview;

  /// A picture the user chose for it, as an absolute path.
  final String? icon;

  String get label => panel.title.isEmpty ? 'Folder' : panel.title;

  /// The key of a panel card's picture in `LauncherConfig.iconOverrides`.
  static String iconKey(String panelId) => 'panel:$panelId';
}

class WidgetEntry extends Entry {
  const WidgetEntry(super.item);
}

/// A pane inside another, with what is in it.
class PaneEntry extends Entry {
  const PaneEntry(super.item, this.view);

  final PaneView view;
}

/// A pane with each of its items matched to what it shows.
@immutable
class PaneView {
  const PaneView(this.pane, this.entries);

  final Pane pane;

  /// One per item of [pane], in order.
  final List<Entry> entries;

  /// Everything in this pane and the panes inside it, other than the panes
  /// themselves.
  Iterable<Entry> get contents => entries.expand(
    (entry) => entry is PaneEntry ? entry.view.contents : [entry],
  );

  /// Whether there is nothing in it but, at most, empty panes.
  bool get isEmpty =>
      entries.every((entry) => entry is PaneEntry && entry.view.isEmpty);
}

@immutable
class PanelView {
  const PanelView(this.panel, this.root);

  final Panel panel;

  /// The pane that fills the panel.
  final PaneView root;

  bool get isEmpty => root.isEmpty;
}

/// The layout with every item matched to the card, panel, widget or pane it
/// stands for: what the TV draws.
@immutable
class LayoutView {
  const LayoutView(this.panels);

  final Map<String, PanelView> panels;

  PanelView get home => panels[Layout.homeId]!;

  /// The sidebars there are, whether or not anything is in them.
  Iterable<PanelView> get bars => [for (final id in Layout.barIds) ?panels[id]];
}

const _previewCount = 4;

/// Matches [config]'s layout against the [cards] there are. Cards placed
/// nowhere appear in the inbox pane, unless the user removed them.
LayoutView resolveLayout(List<LauncherCard> cards, LauncherConfig config) {
  final byId = {for (final card in cards) card.id: card};
  final layout = config.layout.withCards(byId.keys);

  List<LauncherCard> preview(Panel panel) => [
    for (final item in panel.items)
      if (item.kind == ItemKind.card) byId[item.ref]!,
  ].take(_previewCount).toList();

  late PaneView Function(Pane) view;
  Entry entry(LayoutItem item) => switch (item.kind) {
    ItemKind.card => CardEntry(item, byId[item.ref]!),
    ItemKind.widget => WidgetEntry(item),
    ItemKind.pane => PaneEntry(item, view(item.pane!)),
    ItemKind.panel => () {
      final panel = layout.panel(item.ref)!;
      return PanelEntry(
        item,
        panel,
        preview: preview(panel),
        icon: config.iconOverrides[PanelEntry.iconKey(panel.id)],
      );
    }(),
  };
  // Drawn as the pane would have them: see [Pane.shown].
  view = (pane) {
    final shown = pane.withItems(pane.shown);
    return PaneView(shown, shown.items.map(entry).toList());
  };

  return LayoutView({
    for (final panel in layout.panels)
      panel.id: PanelView(panel, view(panel.root)),
  });
}

/// The layout as the TV shows it, kept current with the device and config.
final layoutViewProvider = FutureProvider<LayoutView>((ref) async {
  final cards = await ref.watch(allCardsProvider.future);
  final config = await ref.watch(configProvider.future);
  return resolveLayout(cards, config);
});
