import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/values/template.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// Reads a provider and goes on hearing of it; what a widget and a provider
/// both have.
typedef Watch = T Function<T>(ProviderListenable<T> provider);

/// What variables have been set to while the launcher runs, by the id of
/// the component each is on and then by name. Counts over what the layout
/// says, and is gone when the launcher starts again.
final runtimeVarsProvider =
    NotifierProvider<RuntimeVars, Map<String, Map<String, Object?>>>(
      RuntimeVars.new,
    );

class RuntimeVars extends Notifier<Map<String, Map<String, Object?>>> {
  @override
  Map<String, Map<String, Object?>> build() => const {};

  /// Sets the variable [name] of the component [component] to [value].
  void set(String component, String name, Object? value) => state = {
    ...state,
    component: {...?state[component], name: value},
  };
}

/// What [template] comes to where a name is first looked for among
/// [scope], the variables in reach, and then among everything that can be
/// read by its id: an entity, or a component with variables anyone may
/// read. One value and nothing else is that value, not its text.
Object? readTemplate(Watch watch, String template, Map<String, Object?> scope) {
  final parsed = Template.parse(template);
  final values = {
    for (final root in parsed.roots)
      root: scope.containsKey(root)
          ? scope[root]
          : watch(entityDataProvider(root)) ??
                watch(componentDataProvider(root)),
  };
  return parsed.evaluate((root) => values[root]);
}

/// The variables of one component as they stand, by name.
typedef Scope = ({
  /// Everything the component itself can read.
  Map<String, Object?> own,

  /// What it hands on to what is inside it: all but its private ones.
  Map<String, Object?> inner,

  /// What anything may read of it by its id.
  Map<String, Object?> public,
});

/// Works out [variables], those of the component [id], on top of [outer],
/// what it was handed by whatever it is inside. Each may read those before
/// it. One that holds an entity stands for it: what its id names, among
/// the entities there are and the components that are entities too.
Scope scopeOf(
  Watch watch,
  String id,
  Variables variables,
  Map<String, Object?> outer,
) {
  final runtime = watch(
    runtimeVarsProvider.select((all) => all[id] ?? const <String, Object?>{}),
  );
  final own = {...outer}, inner = {...outer}, public = <String, Object?>{};
  for (final MapEntry(key: name, value: variable) in variables.entries) {
    final raw = runtime.containsKey(name)
        ? runtime[name]
        : variable.result((template) => readTemplate(watch, template, own));
    final value = switch (raw) {
      final String text
          when text.isNotEmpty && variable.type == VarType.entity =>
        watch(entityDataProvider(text)) ??
            watch(componentDataProvider(text)) ??
            raw,
      _ => raw,
    };
    own[name] = value;
    if (variable.access != VarAccess.private) inner[name] = value;
    if (variable.access == VarAccess.public) public[name] = value;
  }
  return (own: own, inner: inner, public: public);
}

/// The variables [item] has: its prefab's, where it is an instance of
/// one, with its own over them.
Variables variablesOf(Component item, Map<String, Prefab> prefabs) =>
    resolved(item, prefabs).vars;

/// The variable that says a folder, or anything else that is shown and
/// hidden, is showing.
const openVar = 'open';

/// What anything may read of the component [id]: its public variables as
/// they stand. A pane also says what it is called and how much is in it,
/// and a folder or a sidebar, which is a pane that is shown and hidden,
/// whether it is `open`. Null where there is no such thing, or nothing to
/// read of it. This is what makes a component an entity.
final componentDataProvider = Provider.autoDispose.family<Object?, String>((
  ref,
  id,
) {
  final found = ref.watch(
    configProvider.select((config) {
      for (final panel in config.value?.layout.panels ?? const <Panel>[]) {
        if (panel.id == id) return (panel: panel, pane: panel.root, item: null);
        for (final component in panel.root.all) {
          if (component.id != id) continue;
          return component.isPane
              ? (panel: null, pane: component, item: null)
              : (panel: null, pane: null, item: component);
        }
      }
      return null;
    }),
  );
  if (found == null) return null;
  final item = found.item, pane = found.pane, panel = found.panel;
  if (item != null) {
    final variables = variablesOf(item, ref.watch(prefabsProvider));
    if (!variables.values.any((v) => v.access == VarAccess.public)) {
      return null;
    }
    // Read from outside, it has only what is its own: nothing handed down.
    return scopeOf(ref.watch, id, variables, const {}).public;
  }
  final label = switch (panel?.title ?? pane!.title) {
    '' => panel == null ? 'Pane' : 'Folder',
    final title => title,
  };
  return {
    'text': label,
    'id': id,
    'label': label,
    'title': panel?.title ?? pane!.title,
    'count': pane!.contents.length,
    // With no picture given it and nothing in it, a folder is drawn in
    // outline, with no frame behind.
    if (panel != null)
      'bare':
          pane.contents.isEmpty &&
          !ref.watch(
            configProvider.select(
              (config) =>
                  config.value?.iconOverrides.containsKey(Panel.iconKey(id)) ??
                  false,
            ),
          ),
    if (panel != null)
      openVar:
          ref.watch(runtimeVarsProvider.select((all) => all[id]?[openVar])) ==
          true,
    ...scopeOf(ref.watch, id, pane.vars, const {}).public,
  };
});
