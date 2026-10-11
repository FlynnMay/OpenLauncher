import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/picture_tile.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/tile_icons.dart';

/// Everything that can be put on the TV: dragged from here onto the screen,
/// or tapped to go where new apps go. Dragging something from the screen
/// back here takes it off.
class Catalogue extends ConsumerStatefulWidget {
  const Catalogue({super.key});

  @override
  ConsumerState<Catalogue> createState() => _CatalogueState();
}

class _CatalogueState extends ConsumerState<Catalogue> {
  String _query = '';

  /// What there is to add, under the heading it is listed under.
  Map<String, List<_Offer>> _offers(Layout layout) {
    final all = ref.watch(entitiesProvider).value ?? const [];
    final widgets = ref.watch(tvStateProvider).value?.widgets ?? const [];
    final prefabs = ref.watch(prefabsProvider);
    final counts = placedCounts(layout);
    // The entities that are not placed of themselves, such as the media
    // player: what they do is offered as buttons that do it.
    final standing = [
      for (final entity in all)
        if (entityKind(entity.kind) case final kind? when !kind.placed) entity,
    ];
    // Named, and given the id that goes with its name, when it is placed.
    final folder = Panel.empty(layout.panelIdFor('Folder'), title: 'Folder');
    _Offer entity(Entity entity) => _Offer(
      Dragged(
        // As the prefab its kind is shown with, at that prefab's size.
        item: () {
          final prefab = prefabs[entityKind(entity.kind)?.prefab];
          return LayoutItem.of(
            entity.id,
            prefab: prefab?.id ?? cardPrefabId,
            w: prefab?.w ?? 1,
            h: prefab?.h ?? 1,
            id: layout.itemIdFor(
              LayoutItem.autoId(entity.id, entity.sourceLabel),
            ),
          );
        }(),
        label: entity.label,
        picture: EntityArt(entity: entity, padding: 4),
      ),
      backed: !EntityArt.isBare(entity),
      count: counts[entity.id] ?? 0,
    );
    List<_Offer> entities(bool Function(Entity entity) which) {
      final offers = all.where(which).map(entity).toList();
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
            item: LayoutItem.pane(Pane(id: layout.paneIdFor()), w: 6, h: 3),
            label: 'Pane',
            picture: const SymbolArt(Icons.dashboard_outlined),
          ),
        ),
        _Offer(
          Dragged(
            item: LayoutItem(
              id: layout.itemIdFor(folder.title),
              kind: ItemKind.panel,
              ref: folder.id,
            ),
            panel: folder,
            label: 'New folder',
            picture: const SymbolArt(Icons.create_new_folder_outlined),
          ),
        ),
        _Offer(
          Dragged.sidebar(
            label: 'Sidebar',
            picture: const SymbolArt(Icons.view_sidebar_outlined),
          ),
        ),
      ],
      'Widgets': [
        for (final widget in widgets)
          _Offer(
            Dragged(
              item: LayoutItem(
                id: layout.itemIdFor(widget.type),
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
      // One for each thing a button can do, ready to be dropped into the
      // quick actions or anywhere else.
      'Buttons': [
        for (final kind in actionKinds)
          // What only one entity does comes below, already told which.
          if (!standing.any(
            (entity) =>
                entityKind(entity.kind)!.actions
                    .any((action) => action.name == kind.name),
          ))
            _Offer(
              Dragged(
                item: actionButton(layout.itemIdFor(kind.label), kind),
                label: kind.label,
                picture: SymbolArt(tileIcons[kind.icon] ?? Icons.smart_button),
              ),
            ),
        for (final entity in standing)
          for (final action in entityKind(entity.kind)!.actions)
            _Offer(
              Dragged(
                item: actionButton(
                  layout.itemIdFor(action.label),
                  action,
                  entity: entity.id,
                ),
                label: action.label,
                picture: SymbolArt(
                  tileIcons[action.icon] ?? Icons.smart_button,
                ),
              ),
            ),
      ],
      'Folders': [
        for (final panel in layout.panels)
          if (panel.kind == PanelKind.popup && panel.id != Layout.menuId)
            _Offer(
              Dragged(
                item: LayoutItem(
                  id: layout.itemIdFor(
                    panel.title.isEmpty ? 'folder' : panel.title,
                  ),
                  kind: ItemKind.panel,
                  ref: panel.id,
                ),
                label: panel.title.isEmpty ? 'Folder' : panel.title,
                picture: const SymbolArt(Icons.folder_outlined),
              ),
            ),
      ],
      // Whatever kinds of entity there are, each under what it is called.
      // Those there is a ready way of showing; the rest are read and
      // acted on by what is put on the screen.
      for (final kind in entityKinds)
        if (kind.prefab != null)
          kind.label: entities((entity) => entity.kind == kind.name),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final layout = ref.watch(configProvider).value?.layout;
    if (layout == null) return const SizedBox.shrink();
    final offers = _offers(layout).map(
      (heading, offers) => MapEntry(heading, [
        for (final offer in offers)
          if (offer.dragged.label.toLowerCase().contains(query)) offer,
      ]),
    )..removeWhere((_, offers) => offers.isEmpty);
    final inbox = Drop(layout.inbox);
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
                  sliver: SliverGrid(
                    gridDelegate: pictureTileGrid,
                    delegate: SliverChildListDelegate([
                      for (final offer in offers)
                        _OfferTile(
                          offer,
                          // A sidebar has no pane to go to, only an edge.
                          onTap: () => offer.dragged.sidebar
                              ? addBarSomewhere(context, ref)
                              : placeDragged(
                                  context,
                                  ref,
                                  offer.dragged,
                                  inbox,
                                ),
                        ),
                    ]),
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

  /// True for a picture that is shown on an entity, as artwork is on the TV.
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
    final label = offer.dragged.label;
    return DragHandle(
      data: offer.dragged,
      child: PictureTile(
        label: label,
        picture: offer.dragged.picture,
        backed: offer.backed,
        badge: switch (offer.count) {
          0 => null,
          1 => 'on TV',
          final count => '×$count',
        },
        tooltip: offer.count == 0 ? label : '$label (on the TV)',
        onTap: onTap,
      ),
    );
  }
}
