import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';
import 'package:test/test.dart';

CommandLogEntry _record(CommandLog log, String session) => log.record(
  session: session,
  action: CommandAction.run,
  command: EditSlice([
    const SliceEdit(ConfigAddress(), [AddScreen(id: 'tv')]),
  ]).toJson(),
);

void main() {
  test('counts what is recorded and tells listeners', () {
    final log = CommandLog();
    final heard = <int>[];
    log.added.listen((entry) => heard.add(entry.revision));
    _record(log, 'one');
    _record(log, 'two');
    expect(log.revision, 2);
    expect(heard, [1, 2]);
  });

  test('says what came after a revision, oldest first', () {
    final log = CommandLog();
    for (var i = 0; i < 4; i++) {
      _record(log, 'one');
    }
    expect([for (final entry in log.after(2)!) entry.revision], [3, 4]);
    expect(log.after(4), isEmpty);
  });

  test('says when what was missed is no longer kept', () {
    final log = CommandLog(limit: 3);
    for (var i = 0; i < 5; i++) {
      _record(log, 'one');
    }
    expect([for (final entry in log.after(2)!) entry.revision], [3, 4, 5]);
    expect(log.after(1), isNull);
  });

  test('an entry is the same when sent as JSON', () {
    final entry = CommandLogEntry(
      revision: 7,
      session: 'phone',
      action: CommandAction.undo,
      command: EditSlice([
        const SliceEdit(ScreenAddress('tv'), [RemoveScreen()]),
      ]).toJson(),
    );
    expect(CommandLogEntry.fromJson(entry.toJson()).toJson(), entry.toJson());
  });
}
