import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/values/values.dart';

/// A template text field with a value picker and a live preview. Committed on
/// Enter or blur.
class TemplateField extends ConsumerStatefulWidget {
  const TemplateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label, value;
  final void Function(String value) onChanged;

  @override
  ConsumerState<TemplateField> createState() => _TemplateFieldState();
}

class _TemplateFieldState extends ConsumerState<TemplateField> {
  /// Most fields of a user value the picker lists.
  static const _mostParts = 40;

  late final _text = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _take();
    });

  void _take() {
    final value = _text.text.trim();
    if (value != widget.value) widget.onChanged(value);
  }

  /// Inserts `{{path}}` at the cursor.
  void _insert(String path) {
    final text = _text.text;
    final at = switch (_text.selection) {
      final selection when selection.isValid => selection,
      _ => TextSelection.collapsed(offset: text.length),
    };
    _text.text = text.replaceRange(at.start, at.end, '{{$path}}');
    _take();
  }

  @override
  void didUpdateWidget(TemplateField old) {
    super.didUpdateWidget(old);
    // Updated from outside while not focused.
    if (widget.value != old.value && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Shows the picker for [values] and inserts the choice.
  Future<void> _choose(Map<String, List<String>> values) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Insert variable'),
        children: [
          for (final MapEntry(key: name, value: paths) in values.entries)
            ExpansionTile(
              title: Text(name),
              children: [
                for (final path in paths)
                  ListTile(
                    dense: true,
                    title: Text('{{$path}}'),
                    onTap: () => Navigator.pop(context, path),
                  ),
              ],
            ),
        ],
      ),
    );
    if (path != null && mounted) _insert(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final own = ref.watch(
      configProvider.select((config) => config.value?.entities ?? const []),
    );
    final fed = [
      for (final entity
          in ref.watch(entitiesProvider).value ?? const <Entity>[])
        if (entity.feed != null && own.byId(entity.id) == null) entity,
    ];
    // Watched so each value's current fields can be offered.
    final values = {
      for (final entity in [...fed, ...own])
        entity.label: [
          entity.id,
          ...valuePaths(
            entity.id,
            ref.watch(valueProvider(entity.id)),
          ).keys.where((path) => path != entity.id).take(_mostParts),
        ],
    };
    final reads = widget.value.contains('{{')
        ? ref.watch(templateProvider(widget.value))
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            focusNode: _focus,
            decoration: InputDecoration(
              labelText: widget.label,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Insert variable',
                icon: const Icon(Icons.data_object),
                onPressed: () => _choose(values),
              ),
            ),
            onSubmitted: (_) => _take(),
          ),
          if (reads != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                reads.isEmpty ? 'Preview: (empty)' : 'Preview: $reads',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
