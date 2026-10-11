import 'package:flutter/material.dart';

/// For settings that make a request: [busy] while pending, errors shown in a
/// snackbar.
mixin Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> whileBusy(Future<void> Function() work) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await work();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$error'.replaceFirst(RegExp(r'^Exception: '), '')),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
