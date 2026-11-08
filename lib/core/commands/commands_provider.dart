import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/command_runner.dart';
import 'package:openlauncher/core/commands/commands_interface.dart';

/// The commands this app runs: on the TV, done to its layout. The web editor
/// replaces it with one that asks the TV.
final commandsProvider = Provider<Commands>((ref) {
  final runner = CommandRunner(ref);
  ref.onDispose(runner.close);
  return runner;
});
