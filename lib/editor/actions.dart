import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/tv_api.dart';

Future<void> _send(
  BuildContext context,
  WidgetRef ref,
  Layout Function(Layout layout) change,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final state = ref.read(editorProvider).value;
  if (state == null) return;
  try {
    await ref.read(editorProvider.notifier).setLayout(change(state.layout));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
  }
}

/// Puts what was dragged where it was dropped, or says why it cannot go
/// there. A new folder is given its name first.
Future<void> placeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
  Drop drop,
) async {
  final layout = ref.read(editorProvider).value?.layout;
  if (layout == null) return;
  if (refusal(layout, dragged.item, drop.pane) case final reason?) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    return;
  }
  var panel = dragged.panel;
  if (panel != null) {
    final name = await _askName(context, panel.title);
    if (name == null || !context.mounted) return;
    panel = Panel(id: panel.id, title: name, root: panel.root);
  }
  await _send(
    context,
    ref,
    (layout) => dropItem(layout, dragged.item, drop, panel: panel),
  );
}

/// Takes what was dragged off the TV.
Future<void> removeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
) => _send(context, ref, (layout) => removeItem(layout, dragged.item.id));

Future<String?> _askName(BuildContext context, String suggested) {
  final name = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Name of the folder'),
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
