import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/busy.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// Asks [find] what was typed and offers what comes back.
class SearchPicker extends StatefulWidget {
  const SearchPicker({
    super.key,
    required this.label,
    required this.said,
    required this.find,
    required this.onChosen,
    this.onCleared,
  });

  final String label;

  /// What is chosen now, or that nothing is.
  final String said;
  final Future<List<FieldHit>> Function(String text) find;
  final void Function(Map<String, Object?> value) onChosen;

  /// Offers a button to forget the choice when given.
  final VoidCallback? onCleared;

  @override
  State<SearchPicker> createState() => _SearchPickerState();
}

class _SearchPickerState extends State<SearchPicker> with Busy<SearchPicker> {
  List<FieldHit>? _found;
  String? _failure;

  Future<void> _search(String text) => whileBusy(() async {
    try {
      final found = await widget.find(text.trim());
      if (mounted) {
        setState(() {
          _found = found;
          _failure = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(widget.said),
      ),
      TextField(
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search),
        ),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty) _search(text);
        },
      ),
      if (_failure case final failure?)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(failure)),
      if (_found case final found?)
        if (found.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No results'),
          )
        else
          for (final hit in found)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(hit.title),
              onTap: () {
                setState(() => _found = null);
                widget.onChosen(hit.value);
              },
            ),
      if (widget.onCleared case final cleared?)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: cleared, child: const Text('Clear')),
        ),
    ],
  );
}
