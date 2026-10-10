import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/launcher_card.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/features/home/card_tile.dart';

/// Everything that can be put on the TV: dragged from here onto the screen,
/// or tapped to go where new apps go. Dragging something from the screen
/// back here takes it off.
class Catalogue extends ConsumerStatefulWidget {
  const Catalogue({super.key, required this.state});

  final TvState state;

  @override
  ConsumerState<Catalogue> createState() => _CatalogueState();
}

class _CatalogueState extends ConsumerState<Catalogue> {
  String _query = '';

  LayoutItem _item(ItemKind kind, String ref) =>
      LayoutItem(id: newId('i'), kind: kind, ref: ref);

  /// What there is to add, under the heading it is listed under.
  Map<String, List<_Offer>> _offers() {
    final state = widget.state;
    final counts = placedCounts(state.layout);
    final folder = Panel(
      id: newId('p'),
      title: 'Folder',
      root: Pane(id: newId('s'), columns: 4),
    );
    _Offer card(LauncherCard card) => _Offer(
      Dragged(
        item: _item(ItemKind.card, card.id),
        label: card.label,
        picture: CardArt(card: card, padding: 4),
      ),
      backed: !CardArt.isBare(card),
      count: counts[card.id] ?? 0,
    );
    List<_Offer> cards(bool Function(LauncherCard card) which) {
      final offers = state.cards.where(which).map(card).toList();
      // What is not on the TV yet comes first; otherwise as the TV has them.
      return [
        ...offers.where((offer) => offer.count == 0),
        ...offers.where((offer) => offer.count != 0),
      ];
    }

    return {
      'Layout': [
        _Offer(
          Dragged(
            item: LayoutItem.pane(Pane(id: newId('s')), w: 6, h: 3),
            label: 'Pane',
            picture: const SymbolArt(Icons.dashboard_outlined),
          ),
        ),
        _Offer(
          Dragged(
            item: _item(ItemKind.panel, folder.id),
            panel: folder,
            label: 'New folder',
            picture: const SymbolArt(Icons.create_new_folder_outlined),
          ),
        ),
      ],
      'Widgets': [
        for (final widget in state.widgets)
          _Offer(
            Dragged(
              item: LayoutItem(
                id: newId('i'),
                kind: ItemKind.widget,
                ref: widget.type,
                w: widget.w,
                h: widget.h,
                options: widget.options,
              ),
              label: widget.label,
              picture: const SymbolArt(Icons.widgets_outlined),
            ),
          ),
      ],
      'Folders': [
        for (final panel in state.layout.panels)
          if (panel.kind == PanelKind.popup)
            _Offer(
              Dragged(
                item: _item(ItemKind.panel, panel.id),
                label: panel.title.isEmpty ? 'Folder' : panel.title,
                picture: const SymbolArt(Icons.folder_outlined),
              ),
            ),
      ],
      'Inputs': cards((card) => card.kind == CardKind.input),
      'Apps': cards((card) => card.kind != CardKind.input),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final offers = _offers().map(
      (heading, offers) => MapEntry(heading, [
        for (final offer in offers)
          if (offer.dragged.label.toLowerCase().contains(query)) offer,
      ]),
    )..removeWhere((_, offers) => offers.isEmpty);
    final inbox = Drop(widget.state.layout.inbox);
    return DragTarget<Dragged>(
      onWillAcceptWithDetails: (details) => details.data.placed,
      onAcceptWithDetails: (details) =>
          removeDragged(context, ref, details.data),
      builder: (context, taking, _) => Stack(
        fit: StackFit.expand,
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              for (final MapEntry(key: heading, value: offers)
                  in offers.entries) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(heading, style: theme.textTheme.titleSmall),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid.extent(
                    maxCrossAxisExtent: 104,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.1,
                    children: [
                      for (final offer in offers)
                        _OfferTile(
                          offer,
                          onTap: () =>
                              placeDragged(context, ref, offer.dragged, inbox),
                        ),
                    ],
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
            ],
          ),
          if (taking.isNotEmpty)
            ColoredBox(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.92),
              child: Center(
                child: Text(
                  'Drop here to take it off the TV',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One thing the catalogue offers.
class _Offer {
  const _Offer(this.dragged, {this.backed = false, this.count = 0});

  final Dragged dragged;

  /// True for a picture that is shown on a card, as artwork is on the TV.
  final bool backed;

  /// How many times it is on the TV already.
  final int count;
}

class _OfferTile extends StatelessWidget {
  const _OfferTile(this.offer, {required this.onTap});

  final _Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = offer.dragged.label;
    return DragHandle(
      data: offer.dragged,
      child: Tooltip(
        message: offer.count == 0 ? label : '$label (on the TV)',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: offer.backed
                            ? theme.colorScheme.surfaceContainerHigh
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: offer.dragged.picture,
                    ),
                    if (offer.count > 0)
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            offer.count == 1 ? 'on TV' : '×${offer.count}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
