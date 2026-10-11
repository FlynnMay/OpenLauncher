import 'package:flutter/material.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/editor/picture_tile.dart';
import 'package:openlauncher/features/home/entity_art.dart';

/// Lets the user choose one of [entities]; null if they choose none.
Future<Entity?> pickEntity(
  BuildContext context, {
  required String title,
  required List<Entity> entities,
}) => showDialog<Entity>(
  context: context,
  builder: (_) => _EntityPicker(title: title, entities: entities),
);

class _EntityPicker extends StatefulWidget {
  const _EntityPicker({required this.title, required this.entities});

  final String title;
  final List<Entity> entities;

  @override
  State<_EntityPicker> createState() => _EntityPickerState();
}

class _EntityPickerState extends State<_EntityPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final entities = [
      for (final entity in widget.entities)
        if (entity.label.toLowerCase().contains(query)) entity,
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
                  for (final entity in entities)
                    PictureTile(
                      label: entity.label,
                      picture: EntityArt(entity: entity, padding: 4),
                      backed: !EntityArt.isBare(entity),
                      onTap: () => Navigator.pop(context, entity),
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
