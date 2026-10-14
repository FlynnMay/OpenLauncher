import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/server/auth_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('openlauncher_auth');
    addTearDown(() => tmp.delete(recursive: true));
  });

  TrustedDevice device(String id) => TrustedDevice(
    id: id,
    tokenHash: 'hash-$id',
    label: id,
    added: DateTime(2026, 10, 14),
    lastSeen: DateTime(2026, 10, 14),
  );

  test('overlapping saves all succeed and the last one is kept', () async {
    final store = FileAuthStore(dir: () async => tmp);
    final devices = [device('a'), device('b')];
    final saves = [store.save(devices)];
    devices.removeWhere((d) => d.id == 'b');
    saves.add(store.save(devices));
    await Future.wait(saves);

    final saved = await store.load();
    expect(saved.map((d) => d.id), ['a']);
    final json = jsonDecode(await File('${tmp.path}/auth.json').readAsString());
    expect(json['devices'], hasLength(1));
  });

  test('a failed save does not stop the next one', () async {
    var calls = 0;
    final store = FileAuthStore(
      dir: () async => calls++ == 0 ? Directory('${tmp.path}/missing') : tmp,
    );
    final failed = store.save([device('a')]);
    final next = store.save([device('b')]);
    await expectLater(failed, throwsA(isA<FileSystemException>()));
    await next;
    expect((await store.load()).map((d) => d.id), ['b']);
  });
}
