import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// Where a node sits in its parent: anchors as fractions of the parent, and
/// its edges in TV pixels from them. On an axis whose anchors meet it has a
/// place and a size; on one stretched, an inset from each side. Greyed, with
/// why, where something else places it.
class TransformSettings extends StatelessWidget {
  const TransformSettings({
    super.key,
    required this.node,
    required this.parentSize,
    required this.onChanged,
    this.placedBy,
  });

  final Node node;

  /// Read when an anchor changes, to keep the node where it is.
  final Size Function() parentSize;

  final void Function(NodeTransform transform) onChanged;

  /// What places it instead, if anything.
  final String? placedBy;

  static const _reach = 4000;

  @override
  Widget build(BuildContext context) {
    final t = node.transform;
    final theme = Theme.of(context);
    void anchored((double, double) x, (double, double) y) =>
        onChanged(withAnchors(node, x, y, parentSize()).transform);
    NodeTransform moved({
      double? left,
      double? top,
      double? right,
      double? bottom,
    }) => NodeTransform(
      minX: t.minX,
      minY: t.minY,
      maxX: t.maxX,
      maxY: t.maxY,
      left: left ?? t.left,
      top: top ?? t.top,
      right: right ?? t.right,
      bottom: bottom ?? t.bottom,
    );
    Widget pixels(String label, double value, void Function(double) set) =>
        NumberField(
          label: label,
          value: value,
          min: -_reach,
          max: _reach,
          decimal: true,
          onChanged: (number) => set(number.toDouble()),
        );
    Widget anchor(String label, double value, void Function(double) set) =>
        NumberField(
          label: label,
          value: value,
          min: 0,
          max: 1,
          step: 0.05,
          decimal: true,
          onChanged: (number) => set(number.toDouble()),
        );
    final pinnedX = t.minX == t.maxX, pinnedY = t.minY == t.maxY;
    final fields = [
      Center(
        child: AnchorPresets(
          x: (t.minX, t.maxX),
          y: (t.minY, t.maxY),
          onPicked: anchored,
        ),
      ),
      const SizedBox(height: 8),
      pixels(pinnedX ? 'X' : 'Left', t.left, (left) {
        // Moved, not stretched, when it has a width of its own.
        onChanged(
          moved(left: left, right: pinnedX ? t.right + left - t.left : null),
        );
      }),
      if (pinnedX)
        pixels(
          'Width',
          t.right - t.left,
          (w) => onChanged(moved(right: t.left + w)),
        )
      else
        pixels('Right', -t.right, (inset) => onChanged(moved(right: -inset))),
      pixels(pinnedY ? 'Y' : 'Top', t.top, (top) {
        onChanged(
          moved(top: top, bottom: pinnedY ? t.bottom + top - t.top : null),
        );
      }),
      if (pinnedY)
        pixels(
          'Height',
          t.bottom - t.top,
          (h) => onChanged(moved(bottom: t.top + h)),
        )
      else
        pixels(
          'Bottom',
          -t.bottom,
          (inset) => onChanged(moved(bottom: -inset)),
        ),
      anchor(
        'Anchor min X',
        t.minX,
        (v) => anchored((v, max(v, t.maxX)), (t.minY, t.maxY)),
      ),
      anchor(
        'Anchor min Y',
        t.minY,
        (v) => anchored((t.minX, t.maxX), (v, max(v, t.maxY))),
      ),
      anchor(
        'Anchor max X',
        t.maxX,
        (v) => anchored((min(v, t.minX), v), (t.minY, t.maxY)),
      ),
      anchor(
        'Anchor max Y',
        t.maxY,
        (v) => anchored((t.minX, t.maxX), (min(v, t.minY), v)),
      ),
    ];
    return Section('Transform', [
      if (placedBy case final by?) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Placed by $by.', style: theme.textTheme.bodySmall),
        ),
        IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields,
            ),
          ),
        ),
      ] else
        ...fields,
    ]);
  }
}
