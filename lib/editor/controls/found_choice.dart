import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/busy.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// A choice whose options are found by asking: [find] is given what was
/// typed. What is chosen shows as chips; picking an option adds it, or
/// replaces the one chosen when only one may be.
class FoundChoice extends StatefulWidget {
  const FoundChoice({
    super.key,
    required this.label,
    required this.chosen,
    required this.find,
    required this.finding,
    required this.multiple,
    required this.onChanged,
    this.most,
    this.help = '',
  });

  final String label, help;

  /// What is chosen now, each as it is kept.
  final List<Object?> chosen;
  final Future<List<FieldHit>> Function(String text) find;
  final FieldFinding finding;
  final bool multiple;
  final int? most;
  final void Function(List<Object?> chosen) onChanged;

  @override
  State<FoundChoice> createState() => _FoundChoiceState();
}

class _FoundChoiceState extends State<FoundChoice> with Busy<FoundChoice> {
  final _text = TextEditingController();
  Timer? _pause;
  List<FieldHit>? _found;
  String? _failure;

  /// Counts the questions, so a slow answer to an old one is ignored.
  var _asked = 0;

  FieldFinding get _finding => widget.finding;

  @override
  void initState() {
    super.initState();
    if (_finding.on == FindOn.filter) _ask('');
  }

  @override
  void dispose() {
    _pause?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _ask(String text) async {
    final turn = ++_asked;
    setState(() => busy = true);
    try {
      final found = await widget.find(text.trim());
      if (mounted && turn == _asked) {
        setState(() {
          _found = found;
          _failure = null;
        });
      }
    } on Object catch (error) {
      if (mounted && turn == _asked) setState(() => _failure = '$error');
    } finally {
      if (mounted && turn == _asked) setState(() => busy = false);
    }
  }

  void _typed(String text) {
    if (_finding.on == FindOn.filter) {
      setState(() {});
      return;
    }
    if (_finding.on != FindOn.type) return;
    _pause?.cancel();
    if (text.trim().length < _finding.minChars) {
      _asked++;
      setState(() {
        _found = null;
        busy = false;
      });
      return;
    }
    _pause = Timer(_finding.debounce, () => _ask(text));
  }

  void _submitted(String text) {
    if (_finding.on == FindOn.enter &&
        text.trim().length >= _finding.minChars) {
      _ask(text);
    }
  }

  bool _isChosen(Object? value) =>
      widget.chosen.any((one) => jsonEquals(one, value));

  void _pick(FieldHit hit) {
    if (!widget.multiple) {
      widget.onChanged([hit.value]);
      _text.clear();
      setState(() => _found = _finding.on == FindOn.filter ? _found : null);
      return;
    }
    widget.onChanged(
      _isChosen(hit.value)
          ? [
              for (final one in widget.chosen)
                if (!jsonEquals(one, hit.value)) one,
            ]
          : [...widget.chosen, hit.value],
    );
  }

  List<FieldHit> get _listed {
    final found = _found ?? const <FieldHit>[];
    if (_finding.on != FindOn.filter) return found;
    final typed = _text.text.trim().toLowerCase();
    return [
      for (final hit in found)
        if (hit.title.toLowerCase().contains(typed)) hit,
    ];
  }

  bool get _atMost =>
      widget.multiple &&
      widget.most != null &&
      widget.chosen.length >= widget.most!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listed = _listed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.chosen.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final one in widget.chosen)
                    InputChip(
                      label: Text(FieldSpec.nameOf(one)),
                      onDeleted: () => widget.onChanged([
                        for (final other in widget.chosen)
                          if (!identical(other, one)) other,
                      ]),
                    ),
                ],
              ),
            ),
          TextField(
            controller: _text,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: _finding.on == FindOn.filter
                  ? 'Filter'
                  : _finding.on == FindOn.enter
                  ? 'Type, then press Enter'
                  : 'Type to search',
              helperText: widget.help.isEmpty ? null : widget.help,
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
            onChanged: _typed,
            onSubmitted: _submitted,
          ),
          if (_failure case final failure?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                failure,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_found != null && !busy && listed.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Nothing found', style: theme.textTheme.bodySmall),
            ),
          if (listed.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: _entries(theme, listed),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _entries(ThemeData theme, List<FieldHit> listed) {
    String? heading;
    final entries = <Widget>[];
    for (final hit in listed) {
      if (hit.group.isNotEmpty && hit.group != heading) {
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: Text(hit.group, style: theme.textTheme.labelSmall),
          ),
        );
      }
      heading = hit.group;
      final chosen = _isChosen(hit.value);
      entries.add(
        ListTile(
          dense: true,
          title: Text(hit.title),
          trailing: chosen ? const Icon(Icons.check, size: 18) : null,
          enabled: chosen || !_atMost,
          onTap: () => _pick(hit),
        ),
      );
    }
    return entries;
  }
}
