import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher_domain/values/values.dart';

/// What `{{root...}}` reads: an entity's data, or a component's public
/// variables.
final valueProvider = Provider.autoDispose.family<Object?, String>(
  (ref, root) =>
      ref.watch(entityDataProvider(root)) ??
      ref.watch(componentDataProvider(root)),
);

/// The rendered text of [source]; notifies only when it changes.
final templateProvider = Provider.autoDispose.family<String, String>(
  (ref, source) => valueText(readTemplate(ref.watch, source, const {})),
);
