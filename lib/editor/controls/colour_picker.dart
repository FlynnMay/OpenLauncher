import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// A swatch that opens the picker; an "add" square when there is no colour.
/// [onChanged] gets null when the colour is removed.
class ColourChip extends StatelessWidget {
  const ColourChip({
    super.key,
    required this.colour,
    required this.onChanged,
    this.tooltip,
  });

  /// 0xAARRGGBB.
  final int? colour;
  final String? tooltip;
  final void Function(int? colour) onChanged;

  static const _size = 34.0;

  @override
  Widget build(BuildContext context) {
    final colour = this.colour;
    final outline = Theme.of(context).colorScheme.outline;
    return Tooltip(
      message: colour == null
          ? tooltip ?? 'Add colour'
          : BoxStyle.colorToCss(colour),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final picked = await showDialog<({int? colour})>(
            context: context,
            builder: (_) => _ColourDialog(colour),
          );
          if (picked != null) onChanged(picked.colour);
        },
        child: Container(
          width: _size,
          height: _size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: outline),
          ),
          child: colour == null
              ? Icon(Icons.add, size: 18, color: outline)
              // Over a checkerboard, to show transparency.
              : CustomPaint(
                  painter: const Checks(),
                  child: ColoredBox(color: Color(colour)),
                ),
        ),
      ),
    );
  }
}

/// The transparency checkerboard.
class Checks extends CustomPainter {
  const Checks();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFDDDDDD);
    final dark = Paint()..color = const Color(0xFF999999);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          (x + y).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(Checks oldDelegate) => false;
}

class _ColourDialog extends StatefulWidget {
  const _ColourDialog(this.initial);

  final int? initial;

  @override
  State<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends State<_ColourDialog> {
  static const _swatches = [
    0xFFFFFF, 0xBDBDBD, 0x616161, 0x212121, 0x000000, 0x5D4037, //
    0xE53935, 0xFB8C00, 0xFDD835, 0x7CB342, 0x43A047, 0x00897B, //
    0x00ACC1, 0x039BE5, 0x1E88E5, 0x3949AB, 0x8E24AA, 0xD81B60,
  ];

  /// RGB and alpha (0 to 255), separately.
  late int _rgb = (widget.initial ?? 0xFFFFFFFF) & 0xFFFFFF;
  late int _alpha = (widget.initial ?? 0xFFFFFFFF) >>> 24;
  late final _hex = TextEditingController(text: _css(_rgb));

  static String _css(int rgb) =>
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  int get _colour => _alpha << 24 | _rgb;

  void _pick(int rgb) => setState(() {
    _rgb = rgb;
    _hex.text = _css(rgb);
  });

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return AlertDialog(
      title: const Text('Colour'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rgb in _swatches)
                  InkWell(
                    onTap: () => _pick(rgb),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | rgb),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: rgb == _rgb ? Colors.lightBlueAccent : outline,
                          width: rgb == _rgb ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: outline),
                  ),
                  child: CustomPaint(
                    painter: const Checks(),
                    child: ColoredBox(color: Color(_colour)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(
                      labelText: 'Hex (#RRGGBB)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (text) {
                      final typed = text.startsWith('#') ? text : '#$text';
                      if (typed.length != 7) return;
                      if (BoxStyle.parseColor(typed) case final colour?) {
                        setState(() => _rgb = colour & 0xFFFFFF);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Opacity'),
                Expanded(
                  child: Slider(
                    value: _alpha * 1.0,
                    max: 255,
                    onChanged: (value) =>
                        setState(() => _alpha = value.round()),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(_alpha / 2.55).round()}%',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (colour: null)),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (colour: _colour)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
