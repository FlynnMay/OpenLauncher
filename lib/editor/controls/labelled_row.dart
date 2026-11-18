import 'package:flutter/material.dart';

class LabelledRow extends StatelessWidget {
  const LabelledRow(this.label, this.child, {super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(child: child),
      ],
    ),
  );
}

/// A label above a control that takes the full width, with a line of [help]
/// under it.
class LabelledColumn extends StatelessWidget {
  const LabelledColumn(this.label, this.child, {super.key, this.help = ''});

  final String label, help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.labelMedium),
          child,
          if (help.isNotEmpty) Text(help, style: theme.bodySmall),
        ],
      ),
    );
  }
}
