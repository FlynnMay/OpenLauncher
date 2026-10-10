import 'package:flutter/material.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/editor/picture_tile.dart';
import 'package:openlauncher/features/home/card_tile.dart';

/// Lets the user choose one of [cards]; null if they choose none.
Future<LauncherCard?> pickCard(
  BuildContext context, {
  required String title,
  required List<LauncherCard> cards,
}) => showDialog<LauncherCard>(
  context: context,
  builder: (_) => _CardPicker(title: title, cards: cards),
);

class _CardPicker extends StatefulWidget {
  const _CardPicker({required this.title, required this.cards});

  final String title;
  final List<LauncherCard> cards;

  @override
  State<_CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends State<_CardPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final cards = [
      for (final card in widget.cards)
        if (card.label.toLowerCase().contains(query)) card,
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView(
                gridDelegate: pictureTileGrid,
                children: [
                  for (final card in cards)
                    PictureTile(
                      label: card.label,
                      picture: CardArt(card: card, padding: 4),
                      backed: !CardArt.isBare(card),
                      onTap: () => Navigator.pop(context, card),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
