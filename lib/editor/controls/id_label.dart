import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An id as `(ID: spotify)`; pressing it copies the id.
class IdLabel extends StatelessWidget {
  const IdLabel(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Copy ID',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await Clipboard.setData(ClipboardData(text: id));
          messenger?.showSnackBar(SnackBar(content: Text('Copied "$id"')));
        },
        child: Text(
          '(ID: $id)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
