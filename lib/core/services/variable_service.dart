import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// Runtime values of components' variables. Runtime only; not saved.
class VariableService {
  VariableService(this._ref);

  final Ref _ref;

  /// Sets [variable] on the node [of] names on the screen shown, else on
  /// [component], the one that asked. A text with `{{ }}` in it is evaluated
  /// now, so a toggle can read its own value.
  Future<String?> set({
    required String variable,
    required Object? value,
    String? of,
    String? component,
  }) async {
    final target = of == null ? component : _idOf(of);
    if (target == null) return null;
    _ref
        .read(runtimeVarsProvider.notifier)
        .set(target, variable, _evaluated(value));
    return null;
  }

  /// The id a node of the screen shown is named with there, else [name].
  String _idOf(String name) =>
      _ref.read(currentScreenProvider)?.find(name)?.id ?? name;

  Object? _evaluated(Object? value) => switch (value) {
    final String text when text.contains('{{') => readTemplate(
      _ref.read,
      text,
      const {},
    ),
    _ => value,
  };
}

final variableServiceProvider = Provider<VariableService>(VariableService.new);
