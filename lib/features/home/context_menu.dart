import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/features/home/focus_tile.dart';

IconData _icon(CardAction action) => switch (action) {
  CardAction.open => Icons.play_arrow_outlined,
  CardAction.info => Icons.info_outline,
  CardAction.forceStop => Icons.cancel_outlined,
  CardAction.uninstall => Icons.delete_outline,
  CardAction.remove => Icons.remove_circle_outline,
};

/// Offers [card]'s quick actions and carries out the one chosen.
///
/// [held] says the OK button that asked for the menu is still down; its
/// release must not choose anything. [open] is what selecting the card does.
Future<void> showCardMenu(
  BuildContext context,
  WidgetRef ref,
  LauncherCard card, {
  required bool held,
  required VoidCallback open,
}) async {
  final actions = ref.read(cardActionsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final offered = await actions.actionsFor(card);
  if (offered.isEmpty || !context.mounted) return;
  final chosen = await showDialog<CardAction>(
    context: context,
    builder: (_) => _CardMenu(card: card, actions: offered, held: held),
  );
  if (chosen == null) return;
  if (chosen == CardAction.open) return open();
  String? message;
  try {
    message = await actions.perform(chosen, card);
  } on Object catch (error) {
    message = 'Could not ${chosen.label.toLowerCase()} ${card.label}: $error';
  }
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CardMenu extends StatefulWidget {
  const _CardMenu({
    required this.card,
    required this.actions,
    required this.held,
  });

  final LauncherCard card;
  final List<CardAction> actions;
  final bool held;

  @override
  State<_CardMenu> createState() => _CardMenuState();
}

class _CardMenuState extends State<_CardMenu> {
  /// False until the OK press that opened the menu has been let go.
  late bool _armed = !widget.held;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (_armed || !isSelectKey(event.logicalKey)) {
          return KeyEventResult.ignored;
        }
        // Still the hold that opened the menu: swallow its repeats.
        if (event is KeyUpEvent) _armed = true;
        return KeyEventResult.handled;
      },
      child: SimpleDialog(
        title: Text(
          widget.card.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        children: [
          for (final (index, action) in widget.actions.indexed)
            ListTile(
              autofocus: index == 0,
              dense: true,
              focusColor: Colors.white24,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(_icon(action)),
              title: Text(action.label),
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
    );
  }
}
