import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';
import 'package:openlauncher/core/style/style.dart';

bool _either(Map<String, Object?> values) =>
    values['across'] == true || values['down'] == true;
bool _hasBar(Map<String, Object?> values) =>
    _either(values) && ScrollModule.bars.contains(values['bar']);

/// Lets its Layout's children run past its box, scrolled to keep the focus
/// in view, with a bar to show how far.
class ScrollModule extends ModuleType {
  const ScrollModule() : super('scroll', 'Scroll', needs: const ['layout']);

  static const bars = ['thumb', 'progress'];

  @override
  List<Field> get fields => [
    const Field('across', 'Horizontal scroll', FieldKind.toggle),
    const Field('down', 'Vertical scroll', FieldKind.toggle),
    const Field(
      'bar',
      'Scroll bar',
      FieldKind.choice,
      unset: 'None',
      choices: {'thumb': 'Thumb', 'progress': 'Progress'},
      when: _either,
    ),
    const Field(
      'show',
      'Show scroll bar',
      FieldKind.choice,
      defaultValue: 'always',
      choices: {'always': 'Always', 'auto': 'While scrolling'},
      when: _hasBar,
    ),
    for (final prop in styleProps)
      if (scrollbarStyle.contains(prop.key)) prop,
  ];
}

const scrollModule = ScrollModule();

extension NodeScroll on Node {
  ModuleValues get scroll => values(scrollModule.name) ?? const {};

  /// What it asks for; whether it can is its Layout's business.
  bool get wantsAcross => scroll['across'] == true;
  bool get wantsDown => scroll['down'] == true;

  /// The bar's kind as asked for: `thumb`, `progress`, or null.
  String? get wantsBar => switch (scroll['bar']) {
    final String bar when ScrollModule.bars.contains(bar) => bar,
    _ => null,
  };

  /// Whether its scroll bar shows only while it scrolls.
  bool get scrollbarHides => scroll['show'] == 'auto';
}
