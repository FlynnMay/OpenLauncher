import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/values/template.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// `ref.watch`, from a widget or a provider.
typedef Watch = T Function<T>(ProviderListenable<T> provider);

/// Runtime values of variables, by component id then name. Override the saved
/// values; not persisted.
final runtimeVarsProvider =
    NotifierProvider<RuntimeVars, Map<String, Map<String, Object?>>>(
      RuntimeVars.new,
    );

class RuntimeVars extends Notifier<Map<String, Map<String, Object?>>> {
  @override
  Map<String, Map<String, Object?>> build() => const {};

  void set(String component, String name, Object? value) => state = {
    ...state,
    component: {...?state[component], name: value},
  };
}

/// Evaluates [template], looking names up in [scope] first, then as entity or
/// component ids.
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

/// A component's variables, evaluated.
typedef Scope = ({
  /// Everything it can read.
  Map<String, Object?> own,

  /// What its children inherit: all but the private ones.
  Map<String, Object?> inner,

  /// What anyone can read by its id.
  Map<String, Object?> public,
});

/// Evaluates [variables] of component [id] on top of [outer]. Each can read
/// the ones before it. An entity-typed one becomes that entity's data.
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

/// [item]'s variables merged over its prefab's.
Variables variablesOf(Component item, Map<String, Prefab> prefabs) =>
    resolved(item, prefabs).vars;

/// The variable that says a folder or sidebar is showing.
const openVar = 'open';

/// What `{{<id>...}}` reads for a component: its public variables. A pane
/// adds `label`, `title` and `count`; a folder or sidebar adds `open`. Null
/// if there is nothing to read.
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
    // From outside it has no inherited scope.
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
    // An empty folder with no picture is drawn as an outline.
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
