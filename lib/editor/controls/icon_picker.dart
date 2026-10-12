import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/editor/controls/choice_box.dart';
import 'package:openlauncher/features/components/pack_icon.dart';

/// Shows the icon picker. Gives the chosen icon's saved name (`set:name`),
/// empty for none, or null if dismissed.
Future<String?> pickIcon(BuildContext context, {String current = ''}) =>
    showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          height: 680,
          child: IconPicker(
            current: current,
            onPicked: (name) => Navigator.pop(context, name),
          ),
        ),
      ),
    );

/// Every icon of the installed packs: by set, by category, and searched by
/// name or by what it shows.
class IconPicker extends ConsumerStatefulWidget {
  const IconPicker({super.key, this.current = '', required this.onPicked});

  /// The saved name of the icon in use.
  final String current;

  /// Told the saved name picked; empty for none.
  final void Function(String name) onPicked;

  @override
  ConsumerState<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends ConsumerState<IconPicker> {
  late String? _set = iconRef(widget.current)?.set;
  int? _category;
  String _query = '';

  /// What is shown, kept until the search changes.
  (IconSet, int?, String)? _searched;
  List<String> _found = const [];

  List<String> _search(IconSet set) {
    final search = (set, _category, _query);
    if (search != _searched) {
      _searched = search;
      _found = set.search(_query, category: _category);
    }
    return _found;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading = ref.watch(iconSetsProvider);
    final sets = loading.value ?? const <IconSet>[];
    final set =
        sets.where((set) => set.id == _set).firstOrNull ?? sets.firstOrNull;
    final found = set == null ? const <String>[] : _search(set);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            spacing: 12,
            children: [
              Text('Icons', style: theme.textTheme.titleLarge),
              if (sets.length > 1)
                SizedBox(
                  width: 190,
                  child: ChoiceBox<String>(
                    value: set?.id,
                    choices: {for (final set in sets) set.id: set.name},
                    onChanged: (id) => setState(() {
                      _set = id;
                      _category = null;
                    }),
                  ),
                ),
              Expanded(
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (text) => setState(() => _query = text),
                ),
              ),
              TextButton(
                onPressed: widget.current.isEmpty
                    ? null
                    : () => widget.onPicked(''),
                child: const Text('No icon'),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (set != null && set.categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, label) in [
                  (null, 'All'),
                  ...set.categories.indexed,
                ])
                  ChoiceChip(
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    selected: _category == index,
                    onSelected: (_) => setState(() => _category = index),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: switch (loading) {
            AsyncValue(:final error?) when !loading.hasValue => Center(
              child: Text('$error'.replaceFirst(RegExp(r'^Exception: '), '')),
            ),
            _ when !loading.hasValue => const Center(
              child: CircularProgressIndicator(),
            ),
            _ when set == null => const Center(
              child: Text('No pack with icons is installed.'),
            ),
            _ when found.isEmpty => const Center(
              child: Text('No icon matches.'),
            ),
            // Built as it scrolls: a set holds thousands.
            _ => GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 92,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.05,
              ),
              itemCount: found.length,
              itemBuilder: (context, index) {
                final name = set.ref(found[index]);
                return _IconTile(
                  key: ValueKey(name),
                  name: name,
                  label: found[index].replaceAll('_', ' '),
                  picked: name == widget.current,
                  onTap: () => widget.onPicked(name),
                );
              },
            ),
          },
        ),
        if (set != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              found.length == set.icons.length
                  ? '${found.length} icons'
                  : '${found.length} of ${set.icons.length} icons',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    super.key,
    required this.name,
    required this.label,
    required this.picked,
    required this.onTap,
  });

  final String name, label;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: picked ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Column(
              spacing: 6,
              children: [
                PackIcon(name, size: 30, color: theme.colorScheme.onSurface),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
