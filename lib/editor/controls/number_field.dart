import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlauncher/editor/controls/labelled_row.dart';

/// A number in an editable box with a button either side; whole unless
/// [decimal]. A null [value] is unset, or mixed when [mixed].
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.mixed = false,
    this.decimal = false,
    this.placeholder,
    this.start,
    this.onCleared,
  });

  final String label;
  final double? value;
  final bool mixed, decimal;
  final int min, max, step;

  /// What an unset value reads as.
  final String? placeholder;

  /// Where stepping from unset begins; [min] if null.
  final int? start;
  final void Function(num value) onChanged;

  /// Returns it to unset; null if it cannot be.
  final VoidCallback? onCleared;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _text = TextEditingController(text: _shown);
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _take();
    });

  /// The value while a button is held; committed on release.
  num? _held;
  Timer? _repeat;

  String get _shown => switch (_held?.toDouble() ?? widget.value) {
    null => '',
    final value when value == value.roundToDouble() => '${value.round()}',
    final value when widget.decimal => '$value',
    final value => value.toStringAsFixed(2),
  };

  /// Within the limits; a whole number is an int.
  num _clamped(num value) {
    final kept = (widget.decimal ? (value * 10000).round() / 10000 : value)
        .clamp(widget.min, widget.max);
    return widget.decimal && kept != kept.roundToDouble() ? kept : kept.round();
  }

  /// The value [times] steps on from [from].
  num _stepped(double? from, int times) => from == null
      ? _clamped(widget.start ?? widget.min)
      : _clamped((widget.decimal ? from : from.round()) + widget.step * times);

  void _step(int times) {
    final next = _stepped(_typed ?? widget.value, times);
    // A changed value comes back through didUpdateWidget.
    if (next == widget.value) {
      _text.text = _shown;
    } else {
      widget.onChanged(next);
    }
  }

  /// What the box holds, if it is a number.
  double? get _typed => double.tryParse(_text.text.trim());

  void _take() {
    final text = _text.text.trim();
    final typed = _typed;
    if (text.isEmpty && widget.value != null && widget.onCleared != null) {
      widget.onCleared!();
    } else if (typed != null && typed != widget.value) {
      final value = _clamped(typed);
      if (value != widget.value) widget.onChanged(value);
    }
    _text.text = _shown;
  }

  void _revert() {
    _text.text = _shown;
    _focus.unfocus();
  }

  void _hold(int times) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) {
      setState(
        () => _held = _stepped(_held?.toDouble() ?? widget.value, times),
      );
      _text.text = _shown;
    });
  }

  void _release() {
    _repeat?.cancel();
    final held = _held;
    if (held == null) return;
    setState(() => _held = null);
    if (held != widget.value) widget.onChanged(held);
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value || widget.mixed != old.mixed) {
      _text.text = _shown;
    }
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _button(String tooltip, IconData icon, int times, bool enabled) =>
      GestureDetector(
        onLongPressStart: enabled ? (_) => _hold(times) : null,
        onLongPressEnd: (_) => _release(),
        onLongPressCancel: _release,
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => _step(times) : null,
          icon: Icon(icon),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final cleared = widget.onCleared;
    return LabelledRow(
      widget.label,
      Row(
        children: [
          _button(
            'Decrease',
            Icons.remove,
            -1,
            value == null || value > widget.min,
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                for (final shift in [false, true]) ...{
                  SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    shift: shift,
                  ): () =>
                      _step(shift ? 10 : 1),
                  SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    shift: shift,
                  ): () =>
                      _step(shift ? -10 : -1),
                },
                const SingleActivator(LogicalKeyboardKey.escape): _revert,
              },
              child: TextField(
                controller: _text,
                focusNode: _focus,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  hintText: widget.mixed ? 'Mixed' : widget.placeholder,
                  suffixIconConstraints: const BoxConstraints(),
                  suffixIcon: value == null || cleared == null
                      ? null
                      : Tooltip(
                          message: 'Reset to default',
                          child: InkResponse(
                            onTap: cleared,
                            radius: 14,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.restart_alt, size: 16),
                            ),
                          ),
                        ),
                ),
                onSubmitted: (_) => _take(),
              ),
            ),
          ),
          _button(
            'Increase',
            Icons.add,
            1,
            value == null || value < widget.max,
          ),
        ],
      ),
    );
  }
}
