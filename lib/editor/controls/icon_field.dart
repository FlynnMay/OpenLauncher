import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/icon_picker.dart';
import 'package:openlauncher/editor/controls/template_field.dart';
import 'package:openlauncher/features/components/pack_icon.dart';

/// An icon's saved name: chosen from the picker, or typed, as a template
/// that reads as one.
class IconField extends StatelessWidget {
  const IconField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label, value;

  /// Told the new name; empty for none.
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A template names no one icon.
    final fixed = value.isNotEmpty && !value.contains('{{');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Tooltip(
          message: 'Choose icon',
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              fixedSize: const Size.square(48),
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () async {
              final picked = await pickIcon(
                context,
                current: fixed ? value : '',
              );
              if (picked != null && picked != value) onChanged(picked);
            },
            child: fixed
                ? PackIcon(value, color: theme.colorScheme.onSurface)
                : const Icon(Icons.interests_outlined),
          ),
        ),
        Expanded(
          child: TemplateField(
            label: label,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
