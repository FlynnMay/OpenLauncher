import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/card_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/pane_settings.dart';
import 'package:openlauncher/editor/picture_settings.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/stage.dart';
import 'package:openlauncher/editor/style_settings.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/widget_settings.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/picture.dart';

BoxStyle _styleOf(LayoutItem item) => item.pane?.style ?? item.style;

/// A pane's look is its own; anything else's is the item's.
LayoutItem _withStyle(LayoutItem item, BoxStyle style) => switch (item.pane) {
  null => item.copyWith(style: style),
  final pane => item.withPane(pane.copyWith(style: style)),
};

/// The settings of what is picked out on the screen. With several things
/// picked out, only what every one of them has is offered, and a change is
/// made to them all; what belongs to one thing alone, such as a card's name
/// and picture, is offered for one thing alone.
class SelectedProperties extends ConsumerWidget {
  const SelectedProperties({super.key, required this.found});

  final List<Found> found;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = {for (final one in found) one.item.id};
    final items = [for (final one in found) one.item];
    final single = items.length == 1 ? items.single : null;
    void change(Layout Function(Layout layout) how) =>
        changeLayout(context, ref, how);
    void each(LayoutItem Function(LayoutItem item) how) =>
        change((layout) => changeItems(layout, ids, (item, _) => how(item)));

    // What every one of the selected things is decides what is offered.
    final allPanes = items.every((item) => item.kind == ItemKind.pane);
    final allNamed = items.every(
      (item) => item.kind == ItemKind.card || item.kind == ItemKind.panel,
    );
    final folders = ref.watch(selectedPanelsProvider);
    final allFolders =
        items.every((item) => item.kind == ItemKind.panel) &&
        folders.length == items.length;
    void eachFolder(Panel Function(Panel panel) how) => change(
      (layout) => folders.keys.fold(
        layout,
        (layout, id) => changePanel(layout, id, how),
      ),
    );
    Panel folder(
      Panel panel, {
      String? title,
      PopupPosition? position,
      PopupSize? size,
    }) => Panel(
      id: panel.id,
      title: title ?? panel.title,
      root: panel.root,
      position: position ?? panel.position,
      size: size ?? panel.size,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (single != null && single.kind == ItemKind.card)
          _CardDetails(cardId: single.ref),
        if (single != null && allFolders)
          _FolderDetails(
            panel: folders.values.single,
            onRenamed: (title) =>
                eachFolder((panel) => folder(panel, title: title)),
          ),
        if (single != null && single.kind == ItemKind.widget)
          WidgetSettings(
            item: single,
            onChanged: (options) =>
                each((item) => item.copyWith(options: options)),
          ),
        Section('Size', [
          NumberStepper(
            label: 'Cells wide',
            value: shared(items.map((item) => item.w)),
            min: 1,
            max: found
                .map((one) => one.parent.columns)
                .reduce((a, b) => a < b ? a : b),
            onChanged: (w) =>
                change((layout) => resizeItems(layout, ids, w: w * 1.0)),
          ),
          NumberStepper(
            label: 'Cells tall',
            value: shared(items.map((item) => item.h)),
            min: 1,
            max: Pane.maxRows,
            onChanged: (h) =>
                change((layout) => resizeItems(layout, ids, h: h * 1.0)),
          ),
        ]),
        if (allNamed)
          Section('Name', [
            TickBox(
              label: 'Show the name',
              value: shared(items.map((item) => !item.hideName)),
              onChanged: (shown) =>
                  each((item) => item.copyWith(hideName: !shown)),
            ),
            LabelledRow(
              'Drawn',
              ChoiceBox<TileLook>(
                value: shared(items.map((item) => item.look)),
                choices: const {
                  TileLook.card: 'Name under the picture',
                  TileLook.row: 'Name beside the picture',
                },
                onChanged: (look) => each((item) => item.copyWith(look: look)),
              ),
            ),
            if (found.any((one) => one.parent.decides))
              Text(
                'The pane this is in decides some of this for all its '
                'cards. What is set here counts again when it stops.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ]),
        StyleSettings(
          styles: [for (final item in items) _styleOf(item)],
          onChanged: (how) =>
              each((item) => _withStyle(item, how(_styleOf(item)))),
        ),
        if (allPanes)
          PaneSettings(
            title: 'Pane',
            panes: [for (final item in items) item.pane!],
            onChanged: (how) => each((item) => item.withPane(how(item.pane!))),
            children: [
              if (single != null && found.single.panel.kind == PanelKind.home)
                TickBox(
                  label: 'New apps go here',
                  value: ref.watch(inboxProvider) == single.pane!.id,
                  onChanged: (here) {
                    if (here) {
                      change((layout) => withInbox(layout, single.pane!.id));
                    }
                  },
                ),
            ],
          ),
        if (allFolders)
          Section('Folder', [
            LabelledRow(
              'Opens',
              ChoiceBox<PopupPosition>(
                value: shared(folders.values.map((panel) => panel.position)),
                choices: const {
                  PopupPosition.center: 'Centre',
                  PopupPosition.bottom: 'Bottom',
                  PopupPosition.left: 'Left',
                  PopupPosition.right: 'Right',
                },
                onChanged: (position) =>
                    eachFolder((panel) => folder(panel, position: position)),
              ),
            ),
            LabelledRow(
              'Size',
              ChoiceBox<PopupSize>(
                value: shared(folders.values.map((panel) => panel.size)),
                choices: const {
                  PopupSize.small: 'Small',
                  PopupSize.medium: 'Medium',
                  PopupSize.large: 'Large',
                },
                onChanged: (size) =>
                    eachFolder((panel) => folder(panel, size: size)),
              ),
            ),
            if (single != null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => TvScreen.openPopup(single.ref),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open it'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await _sure(context) && context.mounted) {
                        ref.read(selectionProvider.notifier).clear();
                        change((layout) => removePanel(layout, single.ref));
                      }
                    },
                    icon: const Icon(Icons.folder_delete_outlined),
                    label: const Text('Delete the folder'),
                  ),
                ],
              ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: FilledButton.tonalIcon(
            onPressed: () => removeSelected(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: Text(
              single != null ? 'Take it off the TV' : 'Take them off the TV',
            ),
          ),
        ),
      ],
    );
  }

  static Future<bool> _sure(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete the folder?'),
          content: const Text(
            'What is in it comes off the TV with it. The apps can be added '
            'again anywhere.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

/// What a card is called and what it looks like, wherever it is placed.
class _CardDetails extends ConsumerStatefulWidget {
  const _CardDetails({required this.cardId});

  final String cardId;

  @override
  ConsumerState<_CardDetails> createState() => _CardDetailsState();
}

class _CardDetailsState extends ConsumerState<_CardDetails>
    with Busy<_CardDetails> {
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(tvApiProvider);
    final cards = ref.watch(allCardsProvider).value ?? const <LauncherCard>[];
    final card = cards.where((card) => card.id == widget.cardId).firstOrNull;
    if (card == null) return const SizedBox.shrink();
    final details = ref.watch(tvStateProvider).value?.details[card.id];
    final borrowed = switch (details?.iconFrom) {
      null => null,
      final from => cards.where((other) => other.id == from).firstOrNull,
    };
    return Section('Card', [
      CommitField(
        label: 'Name',
        value: card.label,
        // Emptied, it goes back to the name the TV has for it.
        onChanged: (name) =>
            whileBusy(() => api.rename(card.id, name.isEmpty ? null : name)),
      ),
      if (details?.renamed ?? false)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy
                ? null
                : () => whileBusy(() => api.rename(card.id, null)),
            child: const Text("Use the TV's name for it"),
          ),
        ),
      PictureSettings(
        picture: CardArt(card: card, padding: 10),
        clearLabel: 'Back to its own picture',
        onPicked: (file) => api.setPicture(card.id, file),
        onCleared: details?.customIcon ?? false
            ? () => api.clearPicture(card.id)
            : null,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final from = await pickCard(
                    context,
                    title: "Use another card's picture",
                    cards: [
                      for (final other in cards)
                        if (other.id != card.id) other,
                    ],
                  );
                  if (from != null) {
                    await whileBusy(() => api.borrowPicture(card.id, from.id));
                  }
                },
          icon: const Icon(Icons.collections_outlined),
          label: Text(
            borrowed == null
                ? "Use another card's picture"
                : 'Showing the picture of ${borrowed.label}',
          ),
        ),
      ),
    ]);
  }
}

/// What a folder is called and the picture on the card that opens it.
class _FolderDetails extends ConsumerWidget {
  const _FolderDetails({required this.panel, required this.onRenamed});

  final Panel panel;
  final void Function(String title) onRenamed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(tvApiProvider);
    final key = PanelEntry.iconKey(panel.id);
    final picture = ref.watch(configProvider).value?.iconOverrides[key];
    return Section('Folder card', [
      CommitField(label: 'Name', value: panel.title, onChanged: onRenamed),
      PictureSettings(
        picture: picture == null
            ? null
            : Image(image: pictureAt(picture), fit: BoxFit.cover),
        empty: 'Shows what is inside',
        clearLabel: 'Back to showing what is inside',
        onPicked: (file) => api.setPicture(key, file),
        onCleared: picture == null ? null : () => api.clearPicture(key),
      ),
    ]);
  }
}
