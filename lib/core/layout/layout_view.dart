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

@immutable
class SectionView {
  const SectionView(this.section, this.entries);

  /// [Section.items] here are exactly the items of [entries], in order.
  final Section section;
  final List<Entry> entries;
}

@immutable
class PanelView {
  const PanelView(this.panel, this.sections);

  final Panel panel;
  final List<SectionView> sections;

  bool get isEmpty => sections.every((section) => section.entries.isEmpty);
}

/// The layout with every item matched to the card, panel or widget it
/// stands for: what the TV draws.
@immutable
class LayoutView {
  const LayoutView(this.panels);

  final Map<String, PanelView> panels;

  PanelView get home => panels[Layout.homeId]!;

  /// The rail on one edge, or null if there is nothing in it.
  PanelView? sidebar(String id) => switch (panels[id]) {
    final view? when !view.isEmpty => view,
    _ => null,
  };
}

const _previewCount = 4;

/// Matches [config]'s layout against the [cards] the device offers. Cards
/// placed nowhere appear in the inbox section, unless the user removed them.
LayoutView resolveLayout(List<LauncherCard> cards, LauncherConfig config) {
  final byId = {for (final card in cards) card.id: card};
  final layout = config.layout.withCards(byId.keys);
  List<LauncherCard> preview(Panel panel) => [
    for (final item in panel.items)
      if (item.kind == ItemKind.card) byId[item.ref]!,
  ].take(_previewCount).toList();

  Entry entry(LayoutItem item) => switch (item.kind) {
    ItemKind.card => CardEntry(item, byId[item.ref]!),
    ItemKind.widget => WidgetEntry(item),
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

  return LayoutView({
    for (final panel in layout.panels)
      panel.id: PanelView(panel, [
        for (final section in panel.sections)
          SectionView(section, section.items.map(entry).toList()),
      ]),
  });
}

/// The layout as the TV shows it, kept current with the device and config.
final layoutViewProvider = FutureProvider<LayoutView>((ref) async {
  final cards = await ref.watch(allCardsProvider.future);
  final config = await ref.watch(configProvider.future);
  return resolveLayout(cards, config);
});
