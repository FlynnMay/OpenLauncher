import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/context_menu.dart';
import 'package:openlauncher/features/home/popup_panel.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/widgets/widget_tile.dart';

/// Draws one layout entry and gives it its behaviour: cards open (hold for
/// quick actions), folders show their popup, widgets do their own thing.
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.autofocus = false,
    this.style = TileStyle.card,
    this.inPopup = false,
    this.compact = false,
  });

  final Entry entry;
  final bool autofocus;
  final TileStyle style;

  /// True inside a popup, which closes when one of its cards is opened.
  final bool inPopup;

  /// True in a closed rail, where there is only room for a picture.
  final bool compact;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    LauncherCard card,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(cardActionsProvider);
    if (inPopup) Navigator.of(context).pop();
    try {
      await actions.launch(card);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${card.label}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = this.entry;
    switch (entry) {
      case CardEntry(:final card):
        return ArtTile(
          label: card.label,
          art: CardArt(card: card, padding: style == TileStyle.card ? 14 : 4),
          bare: CardArt.isBare(card),
          autofocus: autofocus,
          style: style,
          showLabel: !compact,
          boxStyle: entry.item.style,
          onSelect: () => _open(context, ref, card),
          onMenu: (held) => showCardMenu(context, ref, card, held: held),
        );
      case PanelEntry():
        return ArtTile(
          label: entry.label,
          art: FolderArt(entry: entry),
          bare: FolderArt.isBare(entry),
          autofocus: autofocus,
          style: style,
          showLabel: !compact,
          boxStyle: entry.item.style,
          onSelect: () => showPanelPopup(context, entry.panel.id),
        );
      case WidgetEntry(:final item):
        return StyledBox(
          style: item.style,
          radius: 10,
          padding: const EdgeInsets.all(8),
          child: WidgetTile(item: item, compact: compact),
        );
    }
  }
}
