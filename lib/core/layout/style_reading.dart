import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher_domain/style/style.dart';

bool _written(Object? value) => value is String && value.contains('{{');

/// [style] with template values evaluated, [scope] first.
Style readStyle(Watch watch, Style style, Map<String, Object?> scope) =>
    !style.values.any(_written)
    ? style
    : {
        for (final MapEntry(:key, :value) in style.entries)
          key: _written(value)
              ? readTemplate(watch, value as String, scope)
              : value,
      };
