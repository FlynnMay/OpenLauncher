import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/node.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// Named values its children and others can read; typed, with access.
class VariablesModule extends ModuleType {
  const VariablesModule() : super('variables', 'Variables');

  /// An instance's variable keeps its prefab's type and access unless it
  /// sets its own.
  @override
  ModuleValues merge(ModuleValues under, ModuleValues over) => {
    ...under,
    for (final MapEntry(key: name, :value) in over.entries)
      if (value != null)
        name: Variable.fromJson(value)
            .over(
              under.containsKey(name) ? Variable.fromJson(under[name]) : null,
            )
            .toJson(),
  };
}

const variablesModule = VariablesModule();

final _parsed = Expando<Variables>();

extension NodeVariables on Node {
  Variables get vars => switch (values(variablesModule.name)) {
    final values? => _parsed[values] ??= variablesFromJson(values),
    null => const {},
  };

  /// With [vars] as its variables.
  Node withVars(Variables vars) => withModule(
    variablesModule.name,
    vars.isEmpty ? null : variablesToJson(vars),
  );

  /// Ids held by its entity typed variables.
  Iterable<String> get handed => handedWith(const {});

  /// [handed], with [runtime] values over the saved ones.
  Iterable<String> handedWith(Map<String, Object?> runtime) => [
    for (final MapEntry(key: name, value: variable) in vars.entries)
      if (variable.type == VarType.entity)
        if (runtime.containsKey(name) ? runtime[name] : variable.value
            case final String id when id.isNotEmpty)
          id,
  ];
}
