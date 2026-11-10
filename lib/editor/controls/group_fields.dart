import 'package:flutter/material.dart';

/// Fields kept together under a heading and laid out on a grid [columns]
/// wide. Each part takes its span of the columns; a row wraps when the next
/// part would not fit, and a row that is short leaves its end empty.
class GroupFields extends StatelessWidget {
  const GroupFields({
    super.key,
    required this.parts,
    this.label = '',
    this.help = '',
    this.columns = 1,
  });

  final String label, help;
  final int columns;
  final List<({Widget child, int span})> parts;

  /// The parts in rows, a part never wider than the grid.
  List<List<({Widget child, int span})>> get rows {
    final rows = <List<({Widget child, int span})>>[];
    var used = columns;
    for (final part in parts) {
      final span = part.span.clamp(1, columns);
      if (used + span > columns) {
        rows.add([]);
        used = 0;
      }
      rows.last.add((child: part.child, span: span));
      used += span;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label, style: theme.textTheme.titleSmall),
            ),
          if (help.isNotEmpty) Text(help, style: theme.textTheme.bodySmall),
          for (final row in rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                for (final part in row)
                  Expanded(flex: part.span, child: part.child),
                // A short row keeps the widths of the rows above it.
                if (row.fold(0, (sum, part) => sum + part.span) < columns)
                  Spacer(
                    flex: columns - row.fold(0, (sum, part) => sum + part.span),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
