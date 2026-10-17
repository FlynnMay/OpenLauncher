import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// Which of the TV's widgets it shows.
List<Widget> appWidgetEditor(ModuleEdit edit) => [
  Consumer(
    builder: (context, ref, _) {
      final providers =
          ref.watch(tvStateProvider).value?.widgetProviders ?? const {};
      return LabelledRow(
        'Widget',
        ChoiceBox<String>(
          value: switch (edit.values['provider']) {
            final String id when providers.containsKey(id) => id,
            _ => null,
          },
          choices: providers,
          onChanged: (id) => edit.set('provider', id),
        ),
      );
    },
  ),
  const Text('Display only: the remote cannot select it.'),
  ...edit.fields(),
];
