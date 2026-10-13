import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/actions/actions.dart';

/// Says that the TV does not allow [access], with a way to its screen for
/// it. Nothing while it is allowed.
class AccessNote extends ConsumerWidget {
  const AccessNote(this.access, {super.key});

  final Access access;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final said = await ref
        .read(actionRunnerProvider)
        .run(Act('access', {entityArg: 'system', 'access': access.name}));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          said?.replaceAll('\n', ': ') ?? 'Opened on the TV. Allow it there.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(accessProvider(access)).value != false) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text('${access.label}: not allowed in the TV\'s settings.'),
          OutlinedButton(
            onPressed: () => _open(context, ref),
            child: const Text('Open on the TV'),
          ),
        ],
      ),
    );
  }
}
