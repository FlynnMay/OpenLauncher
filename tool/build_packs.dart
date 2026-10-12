// Zips every pack in packs/ into assets/packs/, from where the launcher
// installs them on first run as it would an uploaded pack. The build scripts
// run it: dart run tool/build_packs.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const _from = 'packs';
const _to = 'assets/packs';

void main() {
  final out = Directory(_to)..createSync(recursive: true);
  for (final old in out.listSync()) {
    if (!old.path.endsWith('.gitkeep')) old.deleteSync(recursive: true);
  }
  // Pack id -> a hash of its zip: what tells the launcher it has changed.
  final index = <String, String>{};
  final packs = Directory(_from).listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final pack in packs) {
    final manifest = File('${pack.path}/pack.json');
    final id = (jsonDecode(manifest.readAsStringSync()) as Map)['id'] as String;
    final files = pack.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final archive = Archive();
    for (final file in files) {
      final name = file.path.substring(pack.path.length + 1);
      // No times, so the same pack always makes the same zip.
      archive.add(
        ArchiveFile.bytes(name.replaceAll(r'\', '/'), file.readAsBytesSync())
          ..lastModTime = 0,
      );
    }
    final zip = ZipEncoder().encodeBytes(
      archive,
      level: DeflateLevel.bestCompression,
      modified: DateTime.utc(1980),
    );
    File('$_to/$id.zip').writeAsBytesSync(zip);
    index[id] = '${getCrc32(zip).toRadixString(16)}-${zip.length}';
    stdout.writeln('Pack: $id, ${files.length} files, ${zip.length} bytes');
  }
  File('$_to/index.json').writeAsStringSync(jsonEncode(index));
}
