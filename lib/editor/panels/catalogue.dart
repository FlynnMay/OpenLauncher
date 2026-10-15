import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher/features/home/entity_art.dart';

/// Everything that can be added: dragged onto the screen or tapped to go to
/// the inbox. Dragging something back here removes it.
class Catalogue extends ConsumerStatefulWidget {
  const Catalogue({super.key});

  @override
  ConsumerState<Catalogue> createState() => _CatalogueState();
}

/// Headings of the categories with more than one entity.
const _categoryLabels = {
  inputCategory: 'Inputs',
  appCategory: 'Apps',
  launcherCategory: 'Launcher',
};

class _CatalogueState extends ConsumerState<Catalogue> {
  String _query = '';

  static const _memory = ValueKey('catalogue closed');

  /// The headings that are closed.
  late final Set<String> _closed = {
    ...?PageStorage.maybeOf(context)?.readState(context, identifier: _memory)
        as Set<String>?,
  };

  void _toggle(String heading) {
    setState(() {
      if (!_closed.remove(heading)) _closed.add(heading);
    });
    PageStorage.maybeOf(context)
        ?.writeState(context, {..._closed}, identifier: _memory);
  }

  /// The offers, by heading.
  Map<String, List<_Offer>> _offers(LauncherConfig config) {
    // New ids are free in what is being edited; a prefab holds no sidebar or
    // new folder, nor itself.
    final open = ref.watch(editedPrefabProvider);
    final layout = ref.watch(editedLayoutProvider) ?? config.layout;
    final components = ref.watch(tvStateProvider).value?.components ?? const [];
    final prefabs = ref.watch(prefabsProvider);
    final counts = placedCounts(config.layout);
    // Only an entity with a prefab can be placed.
    final all = [
      for (final entity
          in ref.watch(entitiesProvider).value ?? const <Entity>[])
        if (entity.prefab != null) entity,
    ];
    final own = {for (final entity in config.entities) entity.id};
    // Generated entities per category; one alone is a system prefab.
    final sizes = <String, int>{};
    for (final entity in all) {
      if (!own.contains(entity.id)) {
        sizes[entity.category] = (sizes[entity.category] ?? 0) + 1;
      }
    }
    bool alone(Entity entity) => sizes[entity.category] == 1;
    // A pack's ids start with its own; the user's have none.
    String? packOf(String id) => switch (id.indexOf(':')) {
      -1 => null,
      final at => id.substring(0, at),
    };
    final packNames = {
      for (final pack in ref.watch(packsProvider).value ?? const <Pack>[])
        pack.id: pack.name,
    };
    // An edit of a pack's prefab is that prefab, under its pack.
    _Offer? prefabOffer(Prefab prefab) =>
        open != null && holdsPrefab(prefab.id, open.id, prefabs)
        ? null
        : _Offer(
            Dragged(
              item: Component(
                id: layout.itemIdFor(prefab.name),
                prefab: prefab.id,
                w: prefab.root.w,
                h: prefab.root.h,
              ),
              label: prefab.name,
              picture: const SymbolArt(prefabIcon),
            ),
            prefab: prefab,
          );
    // Named and given its final id when placed.
    final folder = folderPane(
      layout.paneIdFor('Folder', 'folder'),
      title: 'Folder',
    );
    _Offer entity(Entity entity) => _Offer(
      Dragged(
        item: instanceFor(entity, layout, prefabs),
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
      'Primitives': [
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
      'Layout': [
        _Offer(
          Dragged(
            item: Component.pane(id: layout.paneIdFor(), w: 6, h: 3),
            label: 'Pane',
            picture: const SymbolArt(Icons.dashboard_outlined),
          ),
        ),
        if (open == null) ...[
          _Offer(
            Dragged.sidebar(
              label: 'Sidebar',
              picture: const SymbolArt(Icons.view_sidebar_outlined),
            ),
          ),
          _Offer(
            Dragged(
              item: Component.of(
                folder.id,
                prefab: folderPrefabId,
                id: layout.itemIdFor(folder.title),
              ),
              folder: folder,
              label: 'New folder',
              picture: const SymbolArt(Icons.create_new_folder_outlined),
            ),
          ),
        ],
      ],
      // Each pack's: its prefabs, and its entities there is one of.
      for (final pack in {
        for (final prefab in prefabs.values) ?packOf(prefab.id),
        for (final entity in all)
          if (!own.contains(entity.id) && alone(entity)) ?packOf(entity.id),
      })
        '${packNames[pack] ?? pack} prefabs': [
          ...entities(
            (entity) =>
                !own.contains(entity.id) &&
                alone(entity) &&
                packOf(entity.id) == pack,
          ),
          for (final prefab in prefabs.values)
            if (packOf(prefab.id) == pack) ?prefabOffer(prefab),
        ],
      'User prefabs': [
        for (final pane in config.layout.docked)
          if (pane.hovers && pane.id != Layout.menuId)
            _Offer(
              Dragged(
                item: Component.of(
                  pane.id,
                  prefab: folderPrefabId,
                  id: layout.itemIdFor(
                    pane.title.isEmpty ? 'folder' : pane.title,
                  ),
                ),
                label: pane.title.isEmpty ? 'Folder' : pane.title,
                picture: const SymbolArt(Icons.folder_outlined),
              ),
            ),
        for (final prefab in prefabs.values)
          if (packOf(prefab.id) == null) ?prefabOffer(prefab),
        ...entities((entity) => own.contains(entity.id)),
      ],
      for (final category in {
        for (final entity in all)
          if (!own.contains(entity.id) && !alone(entity)) entity.category,
      })
        _categoryLabels[category] ?? category: entities(
          (entity) => entity.category == category && !own.contains(entity.id),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final layout = ref.watch(editedLayoutProvider) ?? config.layout;
    final offers = _offers(config).map(
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
                padding: const EdgeInsets.all(12),
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
                SliverToBoxAdapter(
                  child: SectionHeader(
                    heading,
                    // A search shows every match.
                    open: query.isNotEmpty || !_closed.contains(heading),
                    onTap: query.isEmpty ? () => _toggle(heading) : null,
                  ),
                ),
                if (query.isNotEmpty || !_closed.contains(heading))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    sliver: SliverGrid(
                      gridDelegate: pictureTileGrid,
                      delegate: SliverChildListDelegate([
                        for (final offer in offers)
                          _OfferTile(
                            offer,
                            onOpen: switch (offer.prefab) {
                              null => null,
                              final prefab => () => openPrefab(ref, prefab.id),
                            },
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
                  'Drop here to remove',
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
  const _Offer(
    this.dragged, {
    this.backed = false,
    this.count = 0,
    this.prefab,
  });

  final Dragged dragged;

  /// The user's prefab it is a bare instance of, which can be opened.
  final Prefab? prefab;

  /// Whether the picture gets a card background.
  final bool backed;

  /// How many times it is already placed.
  final int count;
}

class _OfferTile extends StatelessWidget {
  const _OfferTile(this.offer, {required this.onTap, this.onOpen});

  final _Offer offer;
  final VoidCallback onTap;
  final VoidCallback? onOpen;

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
        corner: onOpen == null
            ? null
            : IconButton.filledTonal(
                tooltip: 'Open $label',
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                onPressed: onOpen,
                icon: const Icon(Icons.edit_outlined),
              ),
      ),
    );
  }
}
