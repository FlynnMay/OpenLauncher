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
