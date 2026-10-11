import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/values/values.dart';

/// A line of text that values can be written into: a button beside it
/// lists the values there are and puts the one pressed where the cursor
/// is, and under it is how the text reads now. Taken when Enter is pressed
/// or it is left.
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
  /// The most parts of one of the user's values the list offers.
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

  /// Writes the value named by [path] where the cursor is, or at the end.
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
    // Changed from elsewhere, and not being typed in here.
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

  /// Offers [values], the paths there are under what each is called, and
  /// writes in the one chosen.
  Future<void> _choose(Map<String, List<String>> values) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Put a value in'),
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
    final sources = ref.watch(
      configProvider.select((config) => config.value?.sources ?? const []),
    );
    // Kept up to date while the field shows, so that each single thing a
    // value of the user's last answered with can be offered.
    final values = {
      for (final value in builtInValues)
        value.label: [
          value.root,
          for (final part in value.parts) '${value.root}.$part',
        ],
      for (final source in sources)
        (source.name.isEmpty ? source.id : source.name): valuePaths(
          source.id,
          ref.watch(valueProvider(source.id)),
        ).keys.take(_mostParts).toList(),
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
                tooltip: 'Put a value in',
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
                reads.isEmpty ? 'Reads as nothing just now' : 'Reads: $reads',
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
