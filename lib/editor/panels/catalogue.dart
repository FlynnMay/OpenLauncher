import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// The headings and what is under them: the primitives, each pack's, and
  /// the user's.
  List<_Group> _groups(LauncherConfig config) {
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
    // A pack's ids start with its own; the user's have none.
    String? packOf(String id) => switch (id.indexOf(':')) {
      -1 => null,
      final at => id.substring(0, at),
    };
    final categories = ref.watch(categoriesProvider);
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
    // A new sidebar or folder, copied from the template; named and given
    // its final id when placed.
    _Offer? templateOffer(Prefab template) {
      if (open != null) return null;
      final tooltip = 'Made from the ${template.name} template';
      if (makesSidebars(template)) {
        return _Offer(
          Dragged.sidebar(
            label: template.name,
            picture: const SymbolArt(Icons.view_sidebar_outlined),
            template: template,
          ),
          prefab: template,
          tooltip: tooltip,
        );
      }
      final folder = folderFrom(
        template,
        layout.paneIdFor(template.name, 'folder'),
        title: template.name,
        used: layout.itemIds,
      );
      // The folder comes with a card that opens it.
      final card = prefabs[template.card]?.instance(
        folder.id,
        id: layout.itemIdFor(folder.title),
      );
      if (card == null) return null;
      return _Offer(
        Dragged(
          item: card,
          folder: folder,
          label: template.name,
          picture: const SymbolArt(Icons.create_new_folder_outlined),
        ),
        prefab: template,
        tooltip: tooltip,
      );
    }

    _Offer? offerOf(Prefab prefab) =>
        prefab.template ? templateOffer(prefab) : prefabOffer(prefab);
    _Offer? entity(Entity entity) =>
        switch (instanceFor(entity, layout, prefabs)) {
          final item? => _Offer(
            Dragged(
              item: item,
              label: entity.label,
              picture: EntityArt(entity: entity, padding: 4),
            ),
            backed: !EntityArt.isBare(entity),
            count: counts[entity.id] ?? 0,
          ),
          null => null,
        };
    List<_Offer> entities(Iterable<Entity> which) {
      final offers = [for (final one in which) ?entity(one)];
      // Unplaced first.
      return [
        ...offers.where((offer) => offer.count == 0),
        ...offers.where((offer) => offer.count != 0),
      ];
    }

    // A pack's templates, prefabs and entities; entities by category, those
    // alone in theirs together.
    _Group packGroup(String pack) {
      final made = [
        for (final entity in all)
          if (!own.contains(entity.id) && packOf(entity.id) == pack) entity,
      ];
      final sizes = <String, int>{};
      for (final entity in made) {
        sizes[entity.category] = (sizes[entity.category] ?? 0) + 1;
      }
      final mine = [
        for (final prefab in prefabs.values)
          if (packOf(prefab.id) == pack) prefab,
      ];
      return _Group(packNames[pack] ?? pack, const [], [
        _Group('Templates', [
          for (final prefab in mine)
            if (prefab.template) ?templateOffer(prefab),
        ]),
        _Group('Prefabs', [
          for (final prefab in mine)
            if (!prefab.template) ?prefabOffer(prefab),
        ]),
        _Group(
          'Entities',
          entities(made.where((entity) => sizes[entity.category] == 1)),
        ),
        for (final MapEntry(key: category, value: size) in sizes.entries)
          if (size > 1)
            _Group(
              categories[category] ?? category,
              entities(made.where((entity) => entity.category == category)),
            ),
      ]);
    }

    return [
      _Group('Primitives', [
        _Offer(
          Dragged(
            item: Component.pane(id: layout.paneIdFor(), w: 6, h: 3),
            label: 'Pane',
            picture: const SymbolArt(Icons.dashboard_outlined),
          ),
        ),
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
      ]),
      for (final pack in {
        for (final prefab in prefabs.values) ?packOf(prefab.id),
        for (final entity in all)
          if (!own.contains(entity.id)) ?packOf(entity.id),
      })
        packGroup(pack),
      _Group('User prefabs', [
        // A card for each folder, as its template has it.
        for (final pane in config.layout.docked)
          if (pane.hovers)
            if (prefabs[(prefabs[pane.template] ??
                            templateFor(pane.dock!, prefabs))
                        ?.card]
                    ?.instance(
                      pane.id,
                      id: layout.itemIdFor(
                        pane.title.isEmpty ? 'folder' : pane.title,
                      ),
                    )
                case final card?)
              _Offer(
                Dragged(
                  item: card,
                  label: pane.title.isEmpty ? 'Folder' : pane.title,
                  picture: const SymbolArt(Icons.folder_outlined),
                ),
              ),
        for (final prefab in prefabs.values)
          if (packOf(prefab.id) == null) ?offerOf(prefab),
        ...entities(
          all.where(
            (entity) => own.contains(entity.id) || packOf(entity.id) == null,
          ),
        ),
      ]),
    ];
  }

  /// [group]'s heading under [path], and while open what is under it.
  List<Widget> _slivers(
    _Group group,
    String query,
    Drop inbox, {
    String path = '',
    int depth = 0,
  }) {
    final key = path.isEmpty ? group.title : '$path/${group.title}';
    // A search shows every match.
    final open = query.isNotEmpty || !_closed.contains(key);
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          group.title,
          open: open,
          depth: depth,
          onTap: query.isEmpty ? () => _toggle(key) : null,
        ),
      ),
      if (open && group.offers.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverGrid(
            gridDelegate: pictureTileGrid,
            delegate: SliverChildListDelegate([
              for (final offer in group.offers)
                _OfferTile(
                  offer,
                  onOpen: switch (offer.prefab) {
                    null => null,
                    final prefab => () => openPrefab(ref, prefab.id),
                  },
                  // A sidebar goes to an edge, not a pane.
                  onTap: () => offer.dragged.sidebar
                      ? addBarSomewhere(
                          context,
                          ref,
                          template: offer.dragged.template,
                        )
                      : placeDragged(context, ref, offer.dragged, inbox),
                ),
            ]),
          ),
        ),
      if (open)
        for (final inner in group.groups)
          ..._slivers(inner, query, inbox, path: key, depth: depth + 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final layout = ref.watch(editedLayoutProvider) ?? config.layout;
    final groups = [
      for (final group in _groups(config)) ?group.matching(query),
    ];
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
              for (final group in groups) ..._slivers(group, query, inbox),
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

/// A heading: what is under it, then the headings under it.
class _Group {
  const _Group(this.title, [this.offers = const [], this.groups = const []]);

  final String title;
  final List<_Offer> offers;
  final List<_Group> groups;

  /// What matches [query], without headings left empty; null if nothing.
  _Group? matching(String query) {
    final offers = [
      for (final offer in this.offers)
        if (offer.dragged.label.toLowerCase().contains(query)) offer,
    ];
    final groups = [for (final group in this.groups) ?group.matching(query)];
    return offers.isEmpty && groups.isEmpty
        ? null
        : _Group(title, offers, groups);
  }
}

class _Offer {
  const _Offer(
    this.dragged, {
    this.backed = false,
    this.count = 0,
    this.prefab,
    this.tooltip,
  });

  /// Says where it comes from, in place of its name.
  final String? tooltip;

  final Dragged dragged;

  /// The prefab it is a bare instance or copy of, which can be opened.
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
        tooltip:
            offer.tooltip ?? (offer.count == 0 ? label : '$label (on the TV)'),
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
