import 'dart:math';

import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';
import 'package:openlauncher/core/layout/placement.dart';

// The measurements sections were drawn with, in the TV's 960-wide pixels.
const _screenWidth = 960.0, _screenHeight = 540.0, _bottom = 27.0;
const _margin = 48.0, _top = 79.0;
const _gapX = 20.0, _gapY = 16.0, _cellRatio = 1.45;
const _titleHeight = 30.0, _between = 24.0;

/// The global pane for what used to be a stack of [sections], each now a
/// pane where it was and as big as it was.
Pane paneFromSections(String panelId, List<Pane> sections) {
  final kind = Panel.kindOf(panelId);
  if (sections.isEmpty) return Panel.empty(panelId).root;
  if (kind == PanelKind.sidebar) {
    return Panel.empty(panelId).root
        .withItems([for (final section in sections) ...section.items]);
  }
  // A popup with one plain section looks the same with its items directly
  // in the global pane.
  if (kind == PanelKind.popup &&
      sections.length == 1 &&
      sections.single.title.isEmpty &&
      sections.single.style.isEmpty) {
    return sections.single;
  }
  // A popup's width depends on its size; the common one is assumed.
  final home = kind == PanelKind.home;
  final width = home ? _screenWidth - 2 * _margin : 0.62 * _screenWidth - 64;
  const columns = Pane.globalColumns;
  final full = home ? _screenWidth : width;
  final strideX = (full - (columns - 1) * _gapX) / columns + _gapX;
  final strideY = (strideX - _gapX) / _cellRatio + _gapY;
  var top = home ? _top : 0.0;
  final items = <LayoutItem>[];
  for (final section in sections) {
    const pad = Pane.defaultPadding;
    final cell =
        (width - 2 * pad - (section.columns - 1) * _gapX) / section.columns;
    final rows = rowCount(
      placeItems(section.items, section.columns, section.mode),
    );
    final content =
        2 * pad +
        (section.title.isEmpty ? 0 : _titleHeight) +
        (rows == 0 ? 0 : rows * (cell / _cellRatio + _gapY) - _gapY);
    // A lone pane on the home screen at least reaches the bottom of it:
    // new apps turn up in it, and it scrolls when they do not fit.
    final height = home && sections.length == 1
        ? max(content, _screenHeight - _top - _bottom)
        : content;
    items.add(
      LayoutItem.pane(
        section,
        x: hundredths((home ? _margin : 0) / strideX),
        y: hundredths(top / strideY),
        w: hundredths((width + _gapX) / strideX),
        h: hundredths((height + _gapY) / strideY),
      ),
    );
    top += height + _between;
  }
  return Pane(
    id: Panel.rootId(panelId),
    mode: PaneMode.free,
    columns: columns,
    items: items,
  );
}
