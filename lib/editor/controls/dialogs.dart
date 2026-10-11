import 'package:flutter/material.dart';

/// A confirmation dialog; [does] is the confirm button's label.
Future<bool> sureToRemove(
  BuildContext context,
  String title,
  String does,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
            child: Text(does),
          ),
        ],
      ),
    ) ??
    false;

/// Asks for a name; null if cancelled.
Future<String?> askName(
  BuildContext context,
  String suggested, {
  String title = 'Folder name',
}) {
  final name = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: name,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, name.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
