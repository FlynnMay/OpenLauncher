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

/// Everything that can be added: dragged onto the screen or tapped to go to
/// the inbox. Dragging something back here removes it.
class Catalogue extends ConsumerStatefulWidget {
  const Catalogue({super.key});

  @override
  ConsumerState<Catalogue> createState() => _CatalogueState();
}

class _CatalogueState extends ConsumerState<Catalogue> {
  String _query = '';

  /// The offers, by heading.
  Map<String, List<_Offer>> _offers(Layout layout) {
    final all = ref.watch(entitiesProvider).value ?? const [];
    final components = ref.watch(tvStateProvider).value?.components ?? const [];
    final prefabs = ref.watch(prefabsProvider);
    final counts = placedCounts(layout);
    // Entities that are not auto-placed, e.g. the media player; their actions
    // are offered as buttons.
    final standing = [
      for (final entity in all)
        if (entityRegistry(entity.category) case final registry?
            when !registry.placed)
          entity,
    ];
    // Named and given its final id when placed.
    final folder = Panel.empty(layout.panelIdFor('Folder'), title: 'Folder');
    _Offer entity(Entity entity) => _Offer(
      Dragged(
        // As its category's prefab, at that prefab's size.
        item: () {
          final prefab = prefabs[entityRegistry(entity.category)?.prefab];
          return Component.of(
            entity.id,
            prefab: prefab?.id ?? cardPrefabId,
            w: prefab?.root.w ?? 1,
            h: prefab?.root.h ?? 1,
            id: layout.itemIdFor(Component.autoId(entity.id, entity.name)),
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
      // Unplaced first.
      return [
        ...offers.where((offer) => offer.count == 0),
        ...offers.where((offer) => offer.count != 0),
      ];
    }

    return {
      'Layout': [
        _Offer(
          Dragged(
            item: Component.pane(id: layout.paneIdFor(), w: 6, h: 3),
            label: 'Pane',
            picture: const SymbolArt(Icons.dashboard_outlined),
          ),
        ),
        _Offer(
          Dragged(
            item: Component.of(
              folder.id,
              prefab: folderPrefabId,
              id: layout.itemIdFor(folder.title),
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
      'Components': [
        for (final component in components)
          _Offer(
            Dragged(
              item: Component(
                id: layout.itemIdFor(component.type),
                kind: component.type,
                w: component.w,
                h: component.h,
                options: component.options,
              ),
              label: component.label,
              picture: const SymbolArt(Icons.widgets_outlined),
            ),
          ),
      ],
      // One button per action.
      'Buttons': [
        for (final action in actionRegistries)
          // Actions of a single entity are listed below.
          if (!standing.any((entity) => actionFor(action.name, entity) != null))
            _Offer(
              Dragged(
                // For use where a `source` is in reach: a prefab, a menu.
                item: actionButton(
                  layout.itemIdFor(action.label),
                  action,
                  entity: sourceEntity,
                ),
                label: action.label,
                picture: SymbolArt(
                  tileIcons[action.icon] ?? Icons.smart_button,
                ),
              ),
            ),
        for (final entity in standing)
          for (final action in entityRegistry(entity.category)!.actions)
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
                item: Component.of(
                  panel.id,
                  prefab: folderPrefabId,
                  id: layout.itemIdFor(
                    panel.title.isEmpty ? 'folder' : panel.title,
                  ),
                ),
                label: panel.title.isEmpty ? 'Folder' : panel.title,
                picture: const SymbolArt(Icons.folder_outlined),
              ),
            ),
      ],
      // Every entity category that has a prefab.
      for (final registry in entityRegistries)
        if (registry.prefab != null)
          registry.label: entities(
            (entity) => entity.category == registry.name,
          ),
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
                          // A sidebar goes to an edge, not a pane.
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

class _Offer {
  const _Offer(this.dragged, {this.backed = false, this.count = 0});

  final Dragged dragged;

  /// Whether the picture gets a card background.
  final bool backed;

  /// How many times it is already placed.
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
